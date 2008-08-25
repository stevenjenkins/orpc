open Camlp4.PreCast
open Ast
open Types
open Error

let rec parse_type t =
  match t with
    | <:ctyp@loc< unit >> -> Unit loc
    | <:ctyp@loc< int >> -> Int loc
    | <:ctyp@loc< int32 >> -> Int32 loc
    | <:ctyp@loc< int64 >> -> Int64 loc
    | <:ctyp@loc< float >> -> Float loc
    | <:ctyp@loc< bool >> -> Bool loc
    | <:ctyp@loc< char >> -> Char loc
    | <:ctyp@loc< string >> -> String loc

    | <:ctyp@loc< '$v$ >> -> Var (loc, v)
    | <:ctyp@loc< $lid:id$ >> -> Apply (loc, None, id, [])

    (* I don't see how to do this one with quotations; $t1$ * $t2$
       gives both the TyTup and the TySta *)
    | TyTup (loc, ts) ->
        let rec parts = function
          | TySta (_, t1, t2) -> parts t1 @ parts t2
          | TyTup (_, t) -> parts t
          | t -> [ parse_type t ] in
        Tuple (loc, parts ts)

    | <:ctyp@loc< { $fs$ } >> ->
      let rec fields = function
        | <:ctyp< $t1$; $t2$ >> -> fields t1 @ fields t2
        | <:ctyp< $lid:id$ : mutable $t$ >> -> [ { f_id = id; f_mut = true; f_typ = parse_type t } ]
        | <:ctyp< $lid:id$ : $t$ >> -> [ { f_id = id; f_mut = false; f_typ = parse_type t } ]
        | t -> ctyp_error t "expected TySem or TyCol" in
      Record (loc, fields fs)

    (* syntax for TySum? *)
    | TySum (loc, ams) ->
        let rec arms = function
          | <:ctyp< $t1$ | $t2$ >> -> arms t1 @ arms t2
          | <:ctyp< $uid:id$ of $t$ >> ->
              let rec parts = function
                | <:ctyp< $t1$ and $t2$ >> -> parts t1 @ parts t2
                | t -> [ parse_type t ] in
              [ id, parts t ]
          | <:ctyp< $uid:id$ >> -> [ id, [] ]
          | t -> ctyp_error t "expected TyOr, TyOf, or TyId" in
        Variant (loc, arms ams)

    | <:ctyp@loc< $t$ array >> -> Array (loc, parse_type t)
    | <:ctyp@loc< $t$ list >> -> List (loc, parse_type t)
    | <:ctyp@loc< $t$ option >> -> Option (loc, parse_type t)

    | <:ctyp@loc< $_$ $_$ >> ->
        let rec apps args = function
            (* TyApp is used for both tupled and nested type application *)
          | <:ctyp< $t2$ $t1$ >> -> apps (parse_type t2 :: args) t1
          | <:ctyp< $lid:id$ >> -> Apply (loc, None, id, args)
          | <:ctyp< $uid:mname$.$lid:id$ >> -> Apply (loc, Some mname, id, args)
          | t -> ctyp_error t "expected TyApp or TyId" in
        apps [] t

    | TyMan (_, _, t) -> parse_type t

    | <:ctyp@loc< $t1$ -> $t2$ >> -> Arrow (loc, parse_type t1, parse_type t2)

    | t -> ctyp_error t "unsupported type"

let parse_typedef loc t =
  let rec types t a =
    match t with
      | TyAnd (_, t1, t2) -> types t1 (types t2 a)
      | TyDcl (loc, id, tvars, t, []) ->
          let tvars =
            List.map
              (function
                | TyQuo (_, v) -> v
                | t -> ctyp_error t "expected type variable")
              tvars in
          let t = parse_type t in
          (loc, tvars, id, t) ::a
    | t -> ctyp_error t "expected type declaration" in
  types t []

let parse_exception loc t =
  match t with
    | <:ctyp< $uid:id$ of $t$ >> ->
      let rec parts = function
        | <:ctyp< $t1$ and $t2$ >> -> parts t1 @ parts t2
        | t -> [ parse_type t ] in
      (loc, id, parts t )
    | <:ctyp< $uid:id$ >> -> (loc, id, [])
    | t -> ctyp_error t "expected TyOr, TyOf, or TyId"

let parse_val loc id t =
  let rec args t a =
    match t with
      | TyArr (_, t1, t2) ->
          let arg =
            match t1 with
              | TyLab (loc, label, t1) -> Labelled (loc, label, parse_type t1)
              | TyOlb (loc, label, t1) -> Optional (loc, label, parse_type t1)
              | _ -> Unlabelled (loc_of_ctyp t1, parse_type t1) in
          args t2 (arg :: a)
      | t -> List.rev a, parse_type t in
  match args t [] with
    | [], _ -> loc_error loc "function must have at least one argument"
    | args, ret -> (loc, id, args, ret)

type s = {
  typedefs : typedef list;
  exceptions : exc list;
  funcs : func list;
  module_types : module_type list;
}

let rec parse_sig_items i a =
  match i with
    | SgNil _ -> a
    | SgSem (_, i1, i2) -> parse_sig_items i1 (parse_sig_items i2 a)
    | SgTyp (loc, t) -> { a with typedefs = parse_typedef loc t :: a.typedefs }
    | SgExc (loc, t) -> { a with exceptions = parse_exception loc t :: a.exceptions }
    | SgVal (loc, id, t) -> { a with funcs = parse_val loc id t :: a.funcs }
    | SgMty (loc, id, MtSig (_, i)) -> { a with module_types = parse_module_type loc id i :: a.module_types }
    | i -> sig_item_error i "expected type, function declaration, or module type"

and parse_module_type loc id i =
  let rec parse_sig_items i a =
    match i with
      | SgNil _ -> a
      | SgSem (_, i1, i2) -> parse_sig_items i1 (parse_sig_items i2 a)
      | SgVal (loc, id, t) -> parse_val loc id t :: a
      | i -> sig_item_error i "expected function declaration" in
  let kind =
    match id with
      | "Sync" -> Sync
      | "Async" -> Async
      | "Lwt" -> Lwt
      | _ -> loc_error loc "unknown interface kind" in
  (loc, kind, parse_sig_items i [])

let parse_interface i =
  let s = { typedefs = []; exceptions = []; funcs = []; module_types = [] } in
  let s = parse_sig_items i s in
  let { typedefs = typedefs; exceptions = excs; funcs = funcs; module_types = mts } = s in
  match s with
    | { funcs = []; module_types = (_, _, _::_)::_ } -> (typedefs, excs, funcs, mts)
    | { funcs = _::_; module_types = [] } -> (typedefs, excs, funcs, mts)
    | _ -> loc_error Loc.ghost "expected simple interface or modules interface"
