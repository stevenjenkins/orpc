(*
 * This file is part of orpc, OCaml signature to ONC RPC generator
 * Copyright (C) 2008 Skydeck, Inc
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA
 *)

open Camlp4.PreCast
open Ast
open Types
open Error

let _ = let module M = Camlp4OCamlRevisedParser.Make(Syntax) in ()
let _ = let module M = Camlp4OCamlParser.Make(Syntax) in ()

module Loc = Camlp4.PreCast.Loc

let do_file fn =
  let print_error loc msg =
    Format.fprintf Format.std_formatter
      "%s at %a\n" msg Loc.print loc;
    Format.print_flush () in
  try
    let ch = open_in fn in
    let st = Stream.of_channel ch in
    let i = Syntax.parse_interf (Loc.mk fn) st in
    let intf = Parse.parse_interface i in
    let intf = Check.check_interface intf in

    let base = Filename.chop_extension fn in
    let mod_base = String.capitalize (Filename.basename base) in
    List.iter
      (fun (ext, gen_mli, gen_ml) ->
        Printers.OCaml.print_interf ~output_file:(base ^ "_" ^ ext ^ ".mli") (gen_mli mod_base intf);
        Printers.OCaml.print_implem ~output_file:(base ^ "_" ^ ext ^ ".ml") (gen_ml mod_base intf))
      [
        "aux", Gen_aux.gen_aux_mli, Gen_aux.gen_aux_ml;
        "clnt", Gen_clnt.gen_clnt_mli, Gen_clnt.gen_clnt_ml;
        "srv", Gen_srv.gen_srv_mli, Gen_srv.gen_srv_ml;
        "trace", Gen_trace.gen_trace_mli, Gen_trace.gen_trace_ml;
      ]
  with
    | Loc.Exc_located (loc, Stream.Error msg) -> print_error loc msg
    | Loc.Exc_located (loc, e) -> print_error loc (Printexc.to_string e)
    | Error (loc, msg) -> print_error loc msg

let args = Arg.align [
]

let _ = Arg.parse args do_file "usage:"
