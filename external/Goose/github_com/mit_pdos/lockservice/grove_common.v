(* autogenerated from github.com/mit-pdos/lockservice/lockservice *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.grove_prelude.

Module RPCVals.
  Definition S := struct.decl [
    "U64_1" :: uint64T;
    "U64_2" :: uint64T
  ].
End RPCVals.

Module RPCRequest.
  Definition S := struct.decl [
    "CID" :: uint64T;
    "Seq" :: uint64T;
    "Args" :: struct.t RPCVals.S
  ].
End RPCRequest.

Module RPCReply.
  Definition S := struct.decl [
    "Stale" :: boolT;
    "Ret" :: uint64T
  ].
End RPCReply.

Definition RpcFunc: ty := (struct.ptrT RPCRequest.S -> struct.ptrT RPCReply.S -> boolT)%ht.
