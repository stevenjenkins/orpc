module type Sync =
sig
  val ping : unit -> unit

  val run : unit -> unit
    (* The controller calls this proc to initiate the action in the worker.
       When it returns, it is assumed that the worker is completely
       finished with everything.
    *)
end

module type Lwt =
sig
  val ping : unit -> unit Lwt.t

  val run : unit -> unit Lwt.t
    (* The controller calls this proc to initiate the action in the worker.
       When it returns, it is assumed that the worker is completely
       finished with everything.
    *)
end
