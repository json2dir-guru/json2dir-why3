(* json2dir driver: the I/O around the code extracted from json2dir.mlw (module Core).
   Reads stdin, hands the bytes to Core.document (proved: UTF-8, JSON, names), then creates
   the tree it returns. OCaml stdlib + Unix only. *)

let fail msg = prerr_endline ("json2dir: " ^ msg); exit 1

let string_of_bytes l =
  let b = Buffer.create 64 in
  let rec go = function
    | Core.BNil -> ()
    | Core.BCons (c, r) -> Buffer.add_char b (Char.chr c); go r in
  go l;
  Buffer.contents b

let read_all ic =
  let buf = Buffer.create 65536 in
  let chunk = Bytes.create 65536 in
  let rec loop () =
    let k = input ic chunk 0 65536 in
    if k > 0 then (Buffer.add_subbytes buf chunk 0 k; loop ()) in
  loop ();
  Buffer.contents buf

let lstat_opt p = try Some (Unix.lstat p) with Unix.Unix_error (Unix.ENOENT, _, _) -> None

let is_dir st = st.Unix.st_kind = Unix.S_DIR

(* RFC 5.2-5.4: remove an existing non-directory (a symlink itself, never its target) *)
let clear p = function
  | None -> ()
  | Some st when is_dir st -> fail (p ^ ": a directory is in the way")
  | Some _ -> Unix.unlink p

let write_file p content executable =
  (* O_EXCL: never write through an entry that appeared after clear *)
  let fd = Unix.openfile p [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC ] 0o666 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      let len = String.length content in
      let off = ref 0 in
      while !off < len do
        off := !off + Unix.write_substring fd content !off (len - !off)
      done;
      if executable then
        Unix.fchmod fd (((Unix.fstat fd).Unix.st_perm land 0o7777) lor 0o111))

(* members come sorted by name bytes and free of duplicates (proved in json2dir.mlw) *)
let rec apply dir = function
  | Core.ENil -> ()
  | Core.ECons (name, node, rest) ->
    let name = string_of_bytes name in
    let p = if dir = "." then name else Filename.concat dir name in
    let existing = lstat_opt p in
    (match node with
     | Core.File s -> clear p existing; write_file p (string_of_bytes s) false
     | Core.Script s -> clear p existing; write_file p (string_of_bytes s) true
     | Core.Link t -> clear p existing; Unix.symlink (string_of_bytes t) p
     | Core.Dir children ->
       (match existing with
        | Some st when is_dir st -> ()
        | Some _ -> Unix.unlink p; Unix.mkdir p 0o777
        | None -> Unix.mkdir p 0o777);
       apply p children);
    apply dir rest

let message code pos =
  let c = Core.(function
      | x when x = e_json -> Printf.sprintf "input is not valid JSON (at byte %d)" pos
      | x when x = e_surrogate -> "string contains an unpaired surrogate"
      | x when x = e_value -> "numbers, true, false and null are not allowed"
      | x when x = e_array -> "an array must be [\"link\", target] or [\"script\", content]"
      | x when x = e_name -> "invalid member name (empty, \".\", \"..\", or contains / or NUL)"
      | x when x = e_link_nul -> "a link target cannot contain NUL"
      | x when x = e_root -> "the root of the document must be an object"
      | x when x = e_utf8 -> "input is not valid UTF-8"
      | _ -> "invalid input") in
  c code

let () =
  if Array.length Sys.argv > 1 then begin
    prerr_endline "usage: json2dir < document.json";
    exit 2
  end;
  set_binary_mode_in stdin true;
  let input = read_all stdin in
  let a = Array.init (String.length input) (fun i -> Char.code input.[i]) in
  let pos = ref 0 in
  match Core.document a pos with
  | exception Core.Fail code -> fail (message code !pos)
  | exception Stack_overflow -> fail "document is nested too deeply"
  | entries ->
    (try apply "." entries with
     | Unix.Unix_error (e, fn, arg) ->
       fail (Printf.sprintf "%s %s: %s" fn arg (Unix.error_message e)));
    exit 0
