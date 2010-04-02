let rec lst_of_list l =
  match l with
    | [] -> Protocol_aux.Nil
    | a::l -> Protocol_aux.Cons (a, lst_of_list l)

module Pp = Protocol_trace.Pp

let main () =
  let c = Protocol_clnt.create_client (Rpc_client.Inet ("localhost", 9007)) Rpc.Tcp in
  let fmt = Format.err_formatter in

  Pp.orpc_trace_pp_add1'call fmt 6;
  Pp.orpc_trace_pp_add1'reply fmt
    (Protocol_clnt.add1 c 6);
  
  Pp.orpc_trace_pp_addN'call fmt ~n:7 6;
  Pp.orpc_trace_pp_addN'reply fmt
    (Protocol_clnt.addN c ~n:7 6);
  
  Pp.orpc_trace_pp_add1_list'call fmt [5;6;7];
  Pp.orpc_trace_pp_add1_list'reply fmt
    (Protocol_clnt.add1_list c [5;6;7]);
  
  Pp.orpc_trace_pp_add1_lst'call fmt (lst_of_list [7;8;9]);
  Pp.orpc_trace_pp_add1_lst'reply fmt
    (Protocol_clnt.add1_lst c (lst_of_list [7;8;9]));
  
  Pp.orpc_trace_pp_add1_pair'call fmt (17, 22);
  Pp.orpc_trace_pp_add1_pair'reply fmt
    (Protocol_clnt.add1_pair c (17, 22));
  
  Pp.orpc_trace_pp_maybe_raise'call fmt true;
  try
    Pp.orpc_trace_pp_maybe_raise'reply fmt
      (Protocol_clnt.maybe_raise c true)
  with e -> Pp.orpc_trace_pp_exn'reply fmt e;
  
  Rpc_client.shut_down c

let main_async () =
  let esys = Unixqueue.create_unix_event_system() in
  let c = Protocol_clnt.create_client ~esys (Rpc_client.Inet ("localhost", 9007)) Rpc.Tcp in
  let fmt = Format.err_formatter in
  
  Pp.orpc_trace_pp_add1'call fmt 6;
  Protocol_clnt.add1'async c 6
    (fun r -> Pp.orpc_trace_pp_add1'reply fmt (r ()));
  
  Pp.orpc_trace_pp_addN'call fmt ~n:7 6;
  Protocol_clnt.addN'async c ~n:7 6
    (fun r -> Pp.orpc_trace_pp_addN'reply fmt (r ()));
  
  Pp.orpc_trace_pp_add1_list'call fmt [5;6;7];
  Protocol_clnt.add1_list'async c [5;6;7]
    (fun r -> Pp.orpc_trace_pp_add1_list'reply fmt (r ()));
  
  Pp.orpc_trace_pp_add1_lst'call fmt (lst_of_list [7;8;9]);
  Protocol_clnt.add1_lst'async c (lst_of_list [7;8;9])
    (fun r -> Pp.orpc_trace_pp_add1_lst'reply fmt (r ()));
  
  Pp.orpc_trace_pp_add1_pair'call fmt (17, 22);
  Protocol_clnt.add1_pair'async c (17, 22)
    (fun r -> Pp.orpc_trace_pp_add1_pair'reply fmt (r ()));
  
  Pp.orpc_trace_pp_maybe_raise'call fmt true;
  Protocol_clnt.maybe_raise'async c true
    (fun r ->
      try Pp.orpc_trace_pp_maybe_raise'reply fmt (r ())
      with e -> Pp.orpc_trace_pp_exn'reply fmt e);
  
  Unixqueue.run esys;
  Rpc_client.shut_down c

;;

main ()
(* main_async () *)

