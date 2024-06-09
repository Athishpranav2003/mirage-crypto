open Format

let print_header name =
  printf
    {|
/*
      Pre-computed %d-bit multiples of the generator point G for the curve %s,
      used for speeding up its scalar multiplication in point_operations.h.

      Generated by %s
*/|}
    Sys.word_size name Sys.argv.(0)

let pp_array elem_fmt fmt arr =
  let fout = fprintf fmt in
  let len = Array.length arr in
  fout "@[<2>{@\n";
  for i = 0 to len - 1 do
    elem_fmt fmt arr.(i);
    if i < len - 1 then printf ",@ " else printf ""
  done;
  fout "@]@,}"

let div_round_up a b = (a / b) + if a mod b = 0 then 0 else 1

let pp_string_words ~wordsize fmt str =
  assert (String.length str * 8 mod wordsize = 0);
  let limbs = String.length str * 8 / wordsize in
  (* Truncate at the beginning (little-endian) *)
  let bytes = Bytes.unsafe_of_string str in
  (* let bytes = rev_str_bytes str in *)
  fprintf fmt "@[<2>{@\n";
  for i = 0 to limbs - 1 do
    let index = i * (wordsize / 8) in
    (if wordsize = 64 then
       let w = Bytes.get_int64_le bytes index in
       fprintf fmt "%#016Lx" w
     else
       let w = Bytes.get_int32_le bytes index in
       fprintf fmt "%#08lx" w);
    if i < limbs - 1 then printf ",@ " else printf ""
  done;
  fprintf fmt "@]@,}"

let check_shape tables =
  let fe_len = String.length tables.(0).(0).(0) in
  let table_len = fe_len * 2 in
  assert (Array.length tables = table_len);
  Array.iter
    (fun x ->
      assert (Array.length x = 15);
      Array.iter
        (fun x ->
          assert (Array.length x = 3);
          Array.iter (fun x -> assert (String.length x = fe_len)) x)
        x)
    tables

let print_tables tables ~wordsize =
  let fe_len = String.length tables.(0).(0).(0) in
  printf "@[<2>static WORD generator_table[%d][15][3][LIMBS] = @," (fe_len * 2);
  pp_array
    (pp_array (pp_array (pp_string_words ~wordsize)))
    std_formatter tables;
  printf "@];@,"

let print_toplevel name wordsize (module P : Mirage_crypto_ec.Dh_dsa) =
  let tables = P.Dsa.Precompute.generator_tables () in
  assert (wordsize = Sys.word_size);
  check_shape tables;
  print_header name;
  if wordsize = 64 then
    printf
      "@[<v>#ifndef ARCH_64BIT@,\
       #error \"Cannot use 64-bit tables on a 32-bit architecture\"@,\
       #endif@,\
       @]"
  else
    printf
      "@[<v>#ifdef ARCH_64BIT@,\
       #error \"Cannot use 32-bit tables on a 64-bit architecture\"@,\
       #endif@,\
       @]";
  print_tables ~wordsize tables

let curves =
  Mirage_crypto_ec.
    [
      ("p256", (module P256 : Dh_dsa));
      ("p384", (module P384));
      ("p521", (module P521));
    ]

let usage () =
  printf "Usage: gen_tables [%a] [64 | 32]@."
    (pp_print_list
       ~pp_sep:(fun fmt () -> pp_print_string fmt " | ")
       pp_print_string)
    (List.map fst curves)

let go =
  let name, curve, wordsize =
    try
      let name, curve =
        List.find (fun (name, _) -> name = Sys.argv.(1)) curves
      in
      (name, curve, int_of_string Sys.argv.(2))
    with _ ->
      usage ();
      exit 1
  in
  print_toplevel name wordsize curve