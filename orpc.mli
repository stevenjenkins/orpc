val x_char : Xdr.xdr_type_term
val x_list : Xdr.xdr_type_term -> Xdr.xdr_type_term
val to_list : (Xdr.xdr_value -> 'a) -> Xdr.xdr_value -> 'a list
val of_list : ('a -> Xdr.xdr_value) -> 'a list -> Xdr.xdr_value
val to_option : (Xdr.xdr_value -> 'a) -> Xdr.xdr_value -> 'a option
val of_option : ('a -> Xdr.xdr_value) -> 'a option -> Xdr.xdr_value

type ('a, 'b) orpc_result = Orpc_success of 'a | Orpc_failure of exn

val to_orpc_result : (Xdr.xdr_value -> 'a) -> (Xdr.xdr_value -> exn) -> Xdr.xdr_value -> ('a, exn) orpc_result
val of_orpc_result : ('a -> Xdr.xdr_value) -> (exn -> Xdr.xdr_value) -> ('a, exn) orpc_result -> Xdr.xdr_value
val xdr_orpc_result : Xdr.xdr_type_term -> Xdr.xdr_type_term -> Xdr.xdr_type_term;;

val pack_orpc_result : (unit -> 'a) -> ('a, exn) orpc_result
val pack_orpc_result_async : (('a -> unit) -> unit) -> (('a, exn) orpc_result -> unit) -> unit
val unpack_orpc_result : ('a, exn) orpc_result -> 'a

val pp_array : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a array -> unit
val pp_list : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a list -> unit
val pp_option : (Format.formatter -> 'a -> unit) -> Format.formatter -> 'a option -> unit

(* a place to stash the session on asynchronous calls. not thread safe, obviously. *)
val session : Rpc_server.session option ref

module type Trace =
sig
  type t
  val trace_call : string -> (Format.formatter -> unit) -> t
  val trace_reply_ok : t -> (Format.formatter -> unit) -> unit
  val trace_reply_exn : t -> exn -> (Format.formatter -> unit) -> unit
end

module Trace_of_formatter (F : sig val formatter : Format.formatter end) : Trace
