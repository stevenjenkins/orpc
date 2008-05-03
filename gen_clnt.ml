open Camlp4.PreCast
open Ast
open S_ast
open Util

module G = Gen_common

let g = Camlp4.PreCast.Loc.ghost

let gen_clnt_mli name intf =
  match intf with
    | Simple (typedefs, funcs) ->
        <:sig_item@g<
          val create_client :
            ?esys:Unixqueue.event_system ->
            ?program_number:Rtypes.uint4 ->
            ?version_number:Rtypes.uint4 ->
            Rpc_client.connector ->
            Rpc.protocol ->
            Rpc_client.t

          val create_portmapped_client :
            ?esys:Unixqueue.event_system ->
            ?program_number:Rtypes.uint4 ->
            ?version_number:Rtypes.uint4 ->
            string ->
            Rpc.protocol ->
            Rpc_client.t

          val create_client2 :
            ?esys:Unixqueue.event_system ->
            ?program_number:Rtypes.uint4 ->
            ?version_number:Rtypes.uint4 ->
            Rpc_client.mode2 ->
            Rpc_client.t ;;

          $sgSem_of_list
            (List.map
                (fun (_, id, args, res) ->
                  <:sig_item@g<
                    val $lid:id$ : Rpc_client.t ->
                      $List.foldi_right
                        (fun _ i t -> <:ctyp@g< $G.aux_type name (G.argi id i)$ -> $t$ >>)
                        args
                        (G.aux_type name (G.res id))$
                  >>)
                funcs)$

(*
          module Sync(C : sig val with_client : (Rpc_client.t -> 'a) -> 'a end) : $G.sync_module_type name mt is$
*)
        >>

    | Modules _ -> raise (Failure "unimplemented")

let gen_clnt_ml name intf =
  let func (_, id, args, res) =
    match args with
      | [] -> assert false
      | [_] ->
          <:str_item@g<
            let $lid:id$ = fun client arg ->
              $G.aux_val name (G.to_res id)$
                (Rpc_client.sync_call client $`str:id$ ($G.aux_val name (G.of_arg id)$ arg))
          >>
      | _ ->
          let (ps, es) = G.vars args in
          <:str_item@g<
            let $lid:id$ = fun client ->
              $List.fold_right
                (fun p e -> <:expr@g< fun $p$ -> $e$ >>)
                ps
                <:expr@g<
                  let arg = ($exCom_of_list es$) in
                  $G.aux_val name (G.to_res id)$
                    (Rpc_client.sync_call client $`str:id$ ($G.aux_val name (G.of_arg id)$ arg))
                >>$
          >> in

(*
  let sync_func (_, id, args, res) ->
    let (ps, es) = G.vars args in
    <:str_item@g<
      let $lid:id$ =
        $List.fold_right
          (fun p e -> <:expr@g< fun $p$ -> $e$ >>)
          ps
          <:expr@g<
            C.with_client (fun c ->
              $List.fold_left
                (fun e v -> <:expr@g< $e$ $v$ >>)
                <:expr@g< $lid:id$ c >>
                es$)
          >>$
    >>
*)

  match intf with
    | Simple (typedefs, funcs) ->
        <:str_item@g<
          let create_client
              ?(esys = Unixqueue.create_unix_event_system())
              ?program_number
              ?version_number
              connector
              protocol =
            Rpc_client.create ?program_number ?version_number esys connector protocol $G.aux_val name "program"$

          let create_portmapped_client ?esys ?program_number ?version_number host protocol =
            create_client ?esys ?program_number ?version_number (Rpc_client.Portmapped host) protocol

          let create_client2
              ?(esys = Unixqueue.create_unix_event_system())
              ?program_number
              ?version_number
              mode2 =
            Rpc_client.create2 ?program_number ?version_number mode2 $G.aux_val name "program"$ esys ;;

          $stSem_of_list (List.map func funcs)$

(*
    module Sync(C : sig val with_client : (Rpc_client.t -> 'a) -> 'a end) =
    struct
      include $uid:name ^ "_aux"$

      $stSem_of_list (List.map sync_func funcs)$
    end
*)
        >>

    | Modules _ -> raise (Failure "unimplemented")
