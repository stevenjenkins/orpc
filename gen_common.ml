open Camlp4.PreCast
open Ast
open S_ast
open Util

let _loc = Camlp4.PreCast.Loc.ghost

let arg id = id ^ "'arg"
let argi id i = id ^ "'arg" ^ string_of_int i
let res id = id ^ "'res"
let res0 id = id ^ "'res0"
let xdr id = "xdr_" ^ id
let xdr_p id = "xdr'" ^ id
let xdr_arg id = "xdr_" ^ id ^ "'arg"
let xdr_res id = "xdr_" ^ id ^ "'res"
let to_ id = "to_" ^ id
let to_p id = "to'" ^ id
let to_arg id = "to_" ^ id ^ "'arg"
let to_res id = "to_" ^ id ^ "'res"
let of_ id = "of_" ^ id
let of_p id = "of'" ^ id
let of_arg id = "of_" ^ id ^ "'arg"
let of_res id = "of_" ^ id ^ "'res"

let aux_id name id = <:ident< $uid:name ^ "_aux"$ . $lid:id$ >>

let string_of_kind = function
  | Sync -> "Sync"
  | Async -> "Async"
  | Lwt -> "Lwt"

let vars l =
  let ps = List.mapi (fun _ i -> <:patt< $lid:"x" ^ string_of_int i$ >>) l in
  let es = List.mapi (fun _ i -> <:expr< $lid:"x" ^ string_of_int i$ >>) l in
  (ps, es)

let arrows ts t =
  List.fold_right
    (fun t a -> <:ctyp< $t$ -> $a$ >>)
    ts
    t

let tapps t ts =
  List.fold_left
    (fun t t' -> <:ctyp< $t'$ $t$ >>)
    t
    ts

let funs ps e =
  List.fold_right
    (fun p e -> <:expr< fun $p$ -> $e$ >>)
    ps
    e

let funs_ids vs e =
  funs (List.map (fun v -> <:patt< $lid:v$ >>) vs) e

let apps e es =
  List.fold_left
    (fun e e' -> <:expr< $e$ $e'$ >>)
    e
    es

let conses es =
  List.fold_right
    (fun e cs -> <:expr< $e$ :: $cs$ >>)
    es
  <:expr< [] >>

let is_uppercase = function
  | 'A' .. 'Z' -> true
  | _ -> false

let qual_id name mode id =
  if is_uppercase id.[0]
  then
    match mode with
      | Simple -> <:ident< $uid:id$ >>
      | Modules _ ->
          match id with
            | "exn" -> <:ident< exn >>
            | _ -> <:ident< $uid:name$.$uid:id$ >>
  else
    match mode with
      | Simple -> <:ident< $lid:id$ >>
      | Modules _ ->
          match id with
            | "exn" -> <:ident< exn >>
            | _ -> <:ident< $uid:name$.$lid:id$ >>

let qual_id_aux name mode id =
  if is_uppercase id.[0]
  then
    match mode with
      | Simple -> <:ident< $uid:name ^ "_aux"$.$uid:id$ >>
      | Modules _ -> <:ident< $uid:name$.$uid:id$ >>
  else
    match mode with
      | Simple -> <:ident< $uid:name ^ "_aux"$.$lid:id$ >>
      | Modules _ -> <:ident< $uid:name$.$lid:id$ >>

let gen_type qual_id t =

  let rec gt = function
    | Unit _ -> <:ctyp< unit >>
    | Int _ -> <:ctyp< int >>
    | Int32 _ -> <:ctyp< int32 >>
    | Int64 _ -> <:ctyp< int64 >>
    | Float _ -> <:ctyp< float >>
    | Bool _ -> <:ctyp< bool >>
    | Char _ -> <:ctyp< char >>
    | String _ -> <:ctyp< string >>

    | Var (_, v) -> <:ctyp< '$v$ >>

    | Tuple (_, parts) ->
        let parts = List.map gt parts in
        TyTup (_loc, tySta_of_list parts)

    | Record (_, fields) ->
        let fields =
          List.map
            (fun f ->
              if f.f_mut
              then <:ctyp< $lid:f.f_id$ : mutable $gt f.f_typ$ >>
              else <:ctyp< $lid:f.f_id$ : $gt f.f_typ$ >>)
            fields in
        <:ctyp< { $tySem_of_list fields$ } >>

    | Variant (_, arms) ->
        let arms =
          List.map
            (fun (id, ts) ->
              let parts = List.map gt ts in
              match parts with
                | [] -> <:ctyp< $uid:id$ >>
                | _ -> <:ctyp< $uid:id$ of $tyAnd_of_list parts$ >>)
          arms in
        TySum (_loc, tyOr_of_list arms)

    | Array (_, t) -> <:ctyp< $gt t$ array >>
    | List (_, t) -> <:ctyp< $gt t$ list >>
    | Option (_, t) -> <:ctyp< $gt t$ option >>

    | Apply (_, mdl, id, args) ->
        List.fold_left
          (fun t a -> <:ctyp< $gt a$ $t$ >>)
          (match mdl with
            | None -> <:ctyp< $id:qual_id id$ >>
            | Some mdl -> <:ctyp< $uid:mdl$.$lid:id$ >>)
          args

    | Arrow _ -> assert false in

  gt t

let args_funs args e =
  let ps =
    List.mapi
      (fun a i ->
        let p = <:patt< $lid:"x" ^ string_of_int i$ >> in
        match a with
          | Unlabelled _ -> p
          | Labelled (_, label, _) -> PaLab (_loc, label, p)
          | Optional (_, label, _) -> PaOlb (_loc, label, p))
      args in
  funs ps e

let args_apps e args =
  let es =
    List.mapi
      (fun a i ->
        let e = <:expr< $lid:"x" ^ string_of_int i$ >> in
        match a with
          | Unlabelled _ -> e
          | Labelled (_, label, _) -> ExLab (_loc, label, e)
          | Optional (_, label, _) -> ExOlb (_loc, label, e))
      args in
  apps e es

let args_arrows qual_id args t =
  let ts =
    List.map
      (fun a ->
        let t = gen_type qual_id (typ_of_argtyp a) in
        match a with
          | Unlabelled _ -> t
          | Labelled (_, label, _) -> TyLab (_loc, label, t)
          | Optional (_, label, _) -> TyOlb (_loc, label, t))
      args in
  arrows ts t
