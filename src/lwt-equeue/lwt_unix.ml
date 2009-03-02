(*
 * This file is part of orpc, OCaml signature to ONC RPC generator
 * Copyright (C) 2008 Skydeck, Inc
 * Original file (lwt_unix.ml in the Lwt source distribution) is
 * Copyright (C) 2005-2008 J�r�me Vouillon
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

let sleep d =
  let res = Lwt.wait () in
  if d >= 0.0 then begin
    let es = Lwt_equeue.event_system () in
    let g = es#new_group () in
    es#add_resource g (Unixqueue.Wait (es#new_wait_id ()), d);
    es#add_handler g (fun _ _ e ->
      match e with
        | Unixqueue.Timeout _ ->
            Lwt.wakeup res ();
            es#clear g;
            raise Equeue.Reject
        | Unixqueue.Extra Lwt_equeue.Shutdown ->
            es#clear g;
            raise Equeue.Reject
        | _ -> raise Equeue.Reject)
  end;
  res

let yield () = sleep 0.

let run t =
  (Lwt_equeue.event_system ())#run ();
  match Lwt.poll t with
    | Some v -> v
    | None -> failwith "Lwt_unix: thread did not complete"

(****)

type state = Open | Closed | Aborted of exn

type file_descr = { fd : Unix.file_descr; mutable state: state }

let mk_ch fd =
  Unix.set_nonblock fd;
  { fd = fd; state = Open }

let check_descriptor ch =
  match ch.state with
    Open ->
      ()
  | Aborted e ->
      raise e
  | Closed ->
      raise (Unix.Unix_error (Unix.EBADF, "check_descriptor", ""))

(****)

type watchers = [ `Inputs | `Outputs ]

let inputs = `Inputs
let outputs = `Outputs

exception Retry
exception Retry_write
exception Retry_read

type 'a outcome =
    Success of 'a
  | Exn of exn
  | Requeued

exception Perform_actions of Unix.file_descr

let rec wrap_syscall set ch cont action =
  let res =
    try
      check_descriptor ch;
      Success (action ())
    with
      Retry
    | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _)
    | Sys_blocked_io ->
        (* EINTR because we are catching SIG_CHLD hence the system call
           might be interrupted to handle the signal; this lets us restart
           the system call eventually. *)
        add_action set ch cont action;
        Requeued
    | Retry_read ->
        add_action inputs ch cont action;
        Requeued
    | Retry_write ->
        add_action outputs ch cont action;
        Requeued
    | e ->
        Exn e
  in
  match res with
    Success v ->
      Lwt.wakeup cont v
  | Exn e ->
      Lwt.wakeup_exn cont e
  | Requeued ->
      ()

and add_action set ch cont action =
  (*
    this is a somewhat strange use of Equeue: an Lwt action is a
    one-shot handler, so these handlers remove themselves when they
    are called (the fired flag is because event_system#clear doesn't
    clear the handler immediately, but queues a Terminate event, so a
    handler can be called more than once even though it clears its own
    group). the Shutdown and Perform_actions events are meant to
    broadcast to all actions, so the handlers reject them (and it is
    no harm to reject the input/output events as well).
  *)
  assert (ch.state = Open);
  let es = Lwt_equeue.event_system () in
  let g = es#new_group () in
  let fired = ref false in
  let fire () =
    fired := true;
    es#clear g;
    wrap_syscall set ch cont action;
    raise Equeue.Reject in
  let op =
    match set with
      | `Inputs -> Unixqueue.Wait_in ch.fd
      | `Outputs -> Unixqueue.Wait_out ch.fd in
  let handler =
    match set with
      | `Inputs ->
          (fun _ _ e ->
            match !fired, e with
              | false, Unixqueue.Input_arrived (_, fd)
              | false, Unixqueue.Extra (Perform_actions fd) when fd = ch.fd ->
                  fire ()
              | _, Unixqueue.Extra Lwt_equeue.Shutdown ->
                  es#clear g;
                  raise Equeue.Reject
              | _ -> raise Equeue.Reject)
      | `Outputs ->
          (fun _ _ e ->
            match !fired, e with
              | false, Unixqueue.Output_readiness (_, fd)
              | false, Unixqueue.Extra (Perform_actions fd) when fd = ch.fd ->
                  fire ()
              | _, Unixqueue.Extra Lwt_equeue.Shutdown ->
                  es#clear g;
                  raise Equeue.Reject
              | _ -> raise Equeue.Reject) in
  es#add_resource g (op, -1.);
  es#add_handler g handler

let register_action set ch action =
  let cont = Lwt.wait () in
  add_action set ch cont action;
  cont

(****)

let set_state ch st =
  ch.state <- st;
  let es = Lwt_equeue.event_system () in
  (* run all our handlers for this fd, other handlers will reject *)
  es#add_event (Unixqueue.Extra (Perform_actions ch.fd))

let abort ch e =
  if ch.state <> Closed then
    set_state ch (Aborted e)

let unix_file_descr ch = ch.fd

let of_unix_file_descr fd = mk_ch fd

let read ch buf pos len =
  try
    check_descriptor ch;
    Lwt.return (Unix.read ch.fd buf pos len)
  with
    Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
      register_action inputs ch (fun () -> Unix.read ch.fd buf pos len)
  | e ->
      Lwt.fail e

let write ch buf pos len =
  try
    check_descriptor ch;
    Lwt.return (Unix.write ch.fd buf pos len)
  with
    Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
      register_action outputs ch (fun () -> Unix.write ch.fd buf pos len)
  | e ->
      Lwt.fail e

let wait_read ch = register_action inputs ch (fun () -> ())
let wait_write ch = register_action outputs ch (fun () -> ())

let pipe () =
  let (out_fd, in_fd) = Unix.pipe() in
  (mk_ch out_fd, mk_ch in_fd)

let pipe_in () =
  let (out_fd, in_fd) = Unix.pipe() in
  (mk_ch out_fd, in_fd)

let pipe_out () =
  let (out_fd, in_fd) = Unix.pipe() in
  (out_fd, mk_ch in_fd)

let socket dom typ proto =
  let s = Unix.socket dom typ proto in
  mk_ch s

let shutdown ch shutdown_command =
  check_descriptor ch;
  Unix.shutdown ch.fd shutdown_command

let socketpair dom typ proto =
  let (s1, s2) = Unix.socketpair dom typ proto in
  (mk_ch s1, mk_ch s2)

let accept ch =
  try
    check_descriptor ch;
    register_action inputs ch
      (fun () ->
         let (s, addr) = Unix.accept ch.fd in
         (mk_ch s, addr))
  with e ->
    Lwt.fail e

let check_socket ch =
  register_action outputs ch
    (fun () ->
       try ignore (Unix.getpeername ch.fd) with
         Unix.Unix_error (Unix.ENOTCONN, _, _) ->
           (* Get the socket error *)
           ignore (Unix.read ch.fd " " 0 1))

let connect ch addr =
  try
    check_descriptor ch;
    Unix.connect ch.fd addr;
    Lwt.return ()
  with
    Unix.Unix_error
      ((Unix.EINPROGRESS | Unix.EWOULDBLOCK | Unix.EAGAIN), _, _) ->
        check_socket ch
  | e ->
      Lwt.fail e

let wait _ = failwith "Lwt_unix.wait: not implemented"

let waitpid _ _ = failwith "Lwt_unix.waitpid: not implemented"

let system _ = failwith "Lwt_unix.system: not implemented"

let close ch =
  if ch.state = Closed then check_descriptor ch;
  set_state ch Closed;
  Unix.close ch.fd

let setsockopt ch opt v =
  check_descriptor ch;
  Unix.setsockopt ch.fd opt v

let bind ch addr =
  check_descriptor ch;
  Unix.bind ch.fd addr

let listen ch cnt =
  check_descriptor ch;
  Unix.listen ch.fd cnt

let set_close_on_exec ch =
  check_descriptor ch;
  Unix.set_close_on_exec ch.fd

(****)

(*
type popen_process =
    Process of in_channel * out_channel
  | Process_in of in_channel
  | Process_out of out_channel
  | Process_full of in_channel * out_channel * in_channel

let popen_processes = (Hashtbl.create 7 : (popen_process, int) Hashtbl.t)

let open_proc cmd proc input output toclose =
  match Unix.fork () with
     0 -> if input <> Unix.stdin then begin
            Unix.dup2 input Unix.stdin;
            Unix.close input
          end;
          if output <> Unix.stdout then begin
            Unix.dup2 output Unix.stdout;
            Unix.close output
          end;
          List.iter Unix.close toclose;
          Unix.execv "/bin/sh" [| "/bin/sh"; "-c"; cmd |]
  | id -> Hashtbl.add popen_processes proc id

let open_process_in cmd =
  let (in_read, in_write) = pipe_in () in
  let inchan = in_channel_of_descr in_read in
  open_proc cmd (Process_in inchan) Unix.stdin in_write [in_read];
  Unix.close in_write;
  Lwt.return inchan

let open_process_out cmd =
  let (out_read, out_write) = pipe_out () in
  let outchan = out_channel_of_descr out_write in
  open_proc cmd (Process_out outchan) out_read Unix.stdout [out_write];
  Unix.close out_read;
  Lwt.return outchan

let open_process cmd =
  let (in_read, in_write) = pipe_in () in
  let (out_read, out_write) = pipe_out () in
  let inchan = in_channel_of_descr in_read in
  let outchan = out_channel_of_descr out_write in
  open_proc cmd (Process(inchan, outchan)) out_read in_write
                                           [in_read; out_write];
  Unix.close out_read;
  Unix.close in_write;
  Lwt.return (inchan, outchan)

let open_proc_full cmd env proc input output error toclose =
  match Unix.fork () with
     0 -> Unix.dup2 input Unix.stdin; Unix.close input;
          Unix.dup2 output Unix.stdout; Unix.close output;
          Unix.dup2 error Unix.stderr; Unix.close error;
          List.iter Unix.close toclose;
          Unix.execve "/bin/sh" [| "/bin/sh"; "-c"; cmd |] env
  | id -> Hashtbl.add popen_processes proc id

let open_process_full cmd env =
  let (in_read, in_write) = pipe_in () in
  let (out_read, out_write) = pipe_out () in
  let (err_read, err_write) = pipe_in () in
  let inchan = in_channel_of_descr in_read in
  let outchan = out_channel_of_descr out_write in
  let errchan = in_channel_of_descr err_read in
  open_proc_full cmd env (Process_full(inchan, outchan, errchan))
                 out_read in_write err_write [in_read; out_write; err_read];
  Unix.close out_read;
  Unix.close in_write;
  Unix.close err_write;
  Lwt.return (inchan, outchan, errchan)

let find_proc_id fun_name proc =
  try
    let pid = Hashtbl.find popen_processes proc in
    Hashtbl.remove popen_processes proc;
    pid
  with Not_found ->
    raise (Unix.Unix_error (Unix.EBADF, fun_name, ""))

let close_process_in inchan =
  let pid = find_proc_id "close_process_in" (Process_in inchan) in
  close_in inchan;
  Lwt.bind (waitpid [] pid) (fun (_, status) -> Lwt.return status)

let close_process_out outchan =
  let pid = find_proc_id "close_process_out" (Process_out outchan) in
  close_out outchan;
  Lwt.bind (waitpid [] pid) (fun (_, status) -> Lwt.return status)

let close_process (inchan, outchan) =
  let pid = find_proc_id "close_process" (Process(inchan, outchan)) in
  close_in inchan; close_out outchan;
  Lwt.bind (waitpid [] pid) (fun (_, status) -> Lwt.return status)

let close_process_full (inchan, outchan, errchan) =
  let pid =
    find_proc_id "close_process_full"
                 (Process_full(inchan, outchan, errchan)) in
  close_in inchan; close_out outchan; close_in errchan;
  Lwt.bind (waitpid [] pid) (fun (_, status) -> Lwt.return status)
*)

(****)

(* Monitoring functions *)
let inputs_length () = failwith "Lwt_unix.inputs_length: not implemented"
let outputs_length () = failwith "Lwt_unix.outputs_length: not implemented"
let wait_children_length () = failwith "Lwt_unix.wait_children_length: not implemented"
let get_new_sleeps () = failwith "Lwt_unix.get_new_sleeps: not implemented"
let sleep_queue_size () = failwith "Lwt_unix.sleep_queue_size: not implemented"
