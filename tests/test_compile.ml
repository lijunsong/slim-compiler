open OUnit2
open Parse
open Batteries

(** this test only tests the compilation process. Execution testing is
    in other tests.  *)

let compile (content : string) : unit =
  let ast = Parse.parse_string content in
  let frags = Semant.trans_prog ast in
  let procs, str_frags = List.partition
      (fun frag -> match frag with
         | Translate.F.PROC (_) -> true
         | _ -> false) frags in
  (* generate body *)
  let () = List.iter (fun frag -> match frag with
      | Translate.F.PROC(ir, fm) ->
        let instrs, alloc =
          Canon.linearize ir
          |> Canon.basic_blocks
          |> Canon.trace_schedule
          |> (fun ir ->
              let seq = Ir.seq ir in
              Codegen.codegen fm seq)
          |> Register_allocation.alloc in
        let get_register_name t =
          (* let it fail if it fails *)
          Temp.TempMap.find t alloc
        in
        (* get the body section *)
        let () = List.map (fun i ->
            Codegen.format get_register_name i)
            instrs
                   |> Translate.F.proc_entry_exit3 fm
                   |> (fun _ -> ()) in
        ()
      | _ -> failwith "String fragment found in Proc fragments.")
      procs in
  let data_frags = List.map (fun frag -> match frag with
      | Translate.F.PROC(_) -> failwith "proc found in string frags."
      | Translate.F.STRING(l, s) -> (l, s)) str_frags in
  (* generate data *)
  let data = Codegen.codegen_data data_frags in
  (ignore data)

let assert_pass (s : string) =
  let test ctx =
    compile s
  in
  test

let check_file filename =
  let lines = List.of_enum (File.lines_of filename) in
  let s = String.join "\n" lines in
  assert_pass s

let test_files () : string list =
  let dir = "tests/irgen/" in (** run in project root *)
  let handler = Unix.opendir dir in
  let rec read_all_files result =
    try
      let f = Unix.readdir handler in
      if String.ends_with f ".tig" then
        read_all_files ((dir ^ f) :: result)
      else read_all_files result
    with
      End_of_file -> result
  in
  read_all_files []

let get_external_tests () =
  List.map (fun file ->
      file >:: check_file file)
           (test_files())

let suite =
  "Compilation Check" >::: get_external_tests()

let _ =
  run_test_tt_main suite
