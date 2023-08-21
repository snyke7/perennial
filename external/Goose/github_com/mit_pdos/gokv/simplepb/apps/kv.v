(* autogenerated from github.com/mit-pdos/gokv/simplepb/apps/kv *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.gokv.map_string_marshal.
From Goose Require github_com.mit_pdos.gokv.simplepb.apps.esm.
From Goose Require github_com.mit_pdos.gokv.simplepb.simplelog.
From Goose Require github_com.tchajed.marshal.

From Perennial.goose_lang Require Import ffi.grove_prelude.

(* clerk.go *)

Definition Clerk := struct.decl [
  "cl" :: ptrT
].

Definition MakeClerk: val :=
  rec: "MakeClerk" "confHost" :=
    struct.new Clerk [
      "cl" ::= esm.MakeClerk "confHost"
    ].

(* PutArgs from server.go *)

(* begin arg structs and marshalling *)
Definition PutArgs := struct.decl [
  "Key" :: stringT;
  "Val" :: stringT
].

Definition OP_PUT : expr := #(U8 0).

Definition OP_GET : expr := #(U8 1).

Definition encodePutArgs: val :=
  rec: "encodePutArgs" "args" :=
    let: "enc" := ref_to (slice.T byteT) (NewSliceWithCap byteT #1 (#1 + #8)) in
    SliceSet byteT (![slice.T byteT] "enc") #0 OP_PUT;;
    "enc" <-[slice.T byteT] (marshal.WriteInt (![slice.T byteT] "enc") (StringLength (struct.loadF PutArgs "Key" "args")));;
    "enc" <-[slice.T byteT] (marshal.WriteBytes (![slice.T byteT] "enc") (StringToBytes (struct.loadF PutArgs "Key" "args")));;
    "enc" <-[slice.T byteT] (marshal.WriteBytes (![slice.T byteT] "enc") (StringToBytes (struct.loadF PutArgs "Val" "args")));;
    ![slice.T byteT] "enc".

Definition Clerk__Put: val :=
  rec: "Clerk__Put" "ck" "key" "val" :=
    let: "putArgs" := struct.new PutArgs [
      "Key" ::= "key";
      "Val" ::= "val"
    ] in
    esm.Clerk__ApplyExactlyOnce (struct.loadF Clerk "cl" "ck") (encodePutArgs "putArgs");;
    #().

Definition encodeGetArgs: val :=
  rec: "encodeGetArgs" "args" :=
    let: "enc" := ref_to (slice.T byteT) (NewSliceWithCap byteT #1 #1) in
    SliceSet byteT (![slice.T byteT] "enc") #0 OP_GET;;
    "enc" <-[slice.T byteT] (marshal.WriteBytes (![slice.T byteT] "enc") (StringToBytes "args"));;
    ![slice.T byteT] "enc".

Definition Clerk__Get: val :=
  rec: "Clerk__Get" "ck" "key" :=
    StringFromBytes (esm.Clerk__ApplyReadonly (struct.loadF Clerk "cl" "ck") (encodeGetArgs "key")).

(* clerkpool.go *)

Definition ClerkPool := struct.decl [
  "mu" :: ptrT;
  "cls" :: slice.T ptrT;
  "confHost" :: uint64T
].

Definition MakeClerkPool: val :=
  rec: "MakeClerkPool" "confHost" :=
    struct.new ClerkPool [
      "mu" ::= lock.new #();
      "cls" ::= NewSlice ptrT #0;
      "confHost" ::= "confHost"
    ].

(* TODO: get rid of stale clerks from the ck.cls list?
   TODO: keep failed clerks out of ck.cls list? Maybe f(cl) can return an
   optional error saying "get rid of cl".
   XXX: what's the performance overhead of function pointer here v.s. manually
   inlining the body each time? *)
Definition ClerkPool__doWithClerk: val :=
  rec: "ClerkPool__doWithClerk" "ck" "f" :=
    lock.acquire (struct.loadF ClerkPool "mu" "ck");;
    let: "cl" := ref (zero_val ptrT) in
    (if: (slice.len (struct.loadF ClerkPool "cls" "ck")) > #0
    then
      "cl" <-[ptrT] (SliceGet ptrT (struct.loadF ClerkPool "cls" "ck") #0);;
      struct.storeF ClerkPool "cls" "ck" (SliceSkip ptrT (struct.loadF ClerkPool "cls" "ck") #1);;
      lock.release (struct.loadF ClerkPool "mu" "ck");;
      "f" (![ptrT] "cl");;
      lock.acquire (struct.loadF ClerkPool "mu" "ck");;
      struct.storeF ClerkPool "cls" "ck" (SliceAppend ptrT (struct.loadF ClerkPool "cls" "ck") (![ptrT] "cl"));;
      lock.release (struct.loadF ClerkPool "mu" "ck");;
      #()
    else
      lock.release (struct.loadF ClerkPool "mu" "ck");;
      "cl" <-[ptrT] (MakeClerk (struct.loadF ClerkPool "confHost" "ck"));;
      "f" (![ptrT] "cl");;
      lock.acquire (struct.loadF ClerkPool "mu" "ck");;
      struct.storeF ClerkPool "cls" "ck" (SliceAppend ptrT (struct.loadF ClerkPool "cls" "ck") (![ptrT] "cl"));;
      struct.storeF ClerkPool "cls" "ck" (SliceAppend ptrT (struct.loadF ClerkPool "cls" "ck") (![ptrT] "cl"));;
      struct.storeF ClerkPool "cls" "ck" (SliceAppend ptrT (struct.loadF ClerkPool "cls" "ck") (![ptrT] "cl"));;
      struct.storeF ClerkPool "cls" "ck" (SliceAppend ptrT (struct.loadF ClerkPool "cls" "ck") (![ptrT] "cl"));;
      lock.release (struct.loadF ClerkPool "mu" "ck");;
      #()).

Definition ClerkPool__Put: val :=
  rec: "ClerkPool__Put" "ck" "key" "val" :=
    ClerkPool__doWithClerk "ck" (λ: "ck",
      Clerk__Put "ck" "key" "val";;
      #()
      );;
    #().

Definition ClerkPool__Get: val :=
  rec: "ClerkPool__Get" "ck" "key" :=
    let: "ret" := ref (zero_val stringT) in
    ClerkPool__doWithClerk "ck" (λ: "ck",
      "ret" <-[stringT] (Clerk__Get "ck" "key");;
      #()
      );;
    ![stringT] "ret".

(* server.go *)

Definition KVState := struct.decl [
  "kvs" :: mapT stringT;
  "vnums" :: mapT uint64T;
  "minVnum" :: uint64T
].

Definition decodePutArgs: val :=
  rec: "decodePutArgs" "raw_args" :=
    let: "enc" := ref_to (slice.T byteT) (SliceSkip byteT "raw_args" #1) in
    let: "args" := struct.alloc PutArgs (zero_val (struct.t PutArgs)) in
    let: "l" := ref (zero_val uint64T) in
    let: ("0_ret", "1_ret") := marshal.ReadInt (![slice.T byteT] "enc") in
    "l" <-[uint64T] "0_ret";;
    "enc" <-[slice.T byteT] "1_ret";;
    struct.storeF PutArgs "Key" "args" (StringFromBytes (SliceTake (![slice.T byteT] "enc") (![uint64T] "l")));;
    struct.storeF PutArgs "Val" "args" (StringFromBytes (SliceSkip byteT (![slice.T byteT] "enc") (![uint64T] "l")));;
    "args".

Definition getArgs: ty := stringT.

Definition decodeGetArgs: val :=
  rec: "decodeGetArgs" "raw_args" :=
    StringFromBytes (SliceSkip byteT "raw_args" #1).

(* end of marshalling *)
Definition KVState__put: val :=
  rec: "KVState__put" "s" "args" :=
    MapInsert (struct.loadF KVState "kvs" "s") (struct.loadF PutArgs "Key" "args") (struct.loadF PutArgs "Val" "args");;
    NewSlice byteT #0.

Definition KVState__get: val :=
  rec: "KVState__get" "s" "args" :=
    StringToBytes (Fst (MapGet (struct.loadF KVState "kvs" "s") "args")).

Definition KVState__apply: val :=
  rec: "KVState__apply" "s" "args" "vnum" :=
    (if: (SliceGet byteT "args" #0) = OP_PUT
    then
      let: "args" := decodePutArgs "args" in
      MapInsert (struct.loadF KVState "vnums" "s") (struct.loadF PutArgs "Key" "args") "vnum";;
      KVState__put "s" "args"
    else
      (if: (SliceGet byteT "args" #0) = OP_GET
      then
        let: "key" := decodeGetArgs "args" in
        MapInsert (struct.loadF KVState "vnums" "s") "key" "vnum";;
        KVState__get "s" "key"
      else
        Panic "unexpected op type";;
        #())).

Definition KVState__applyReadonly: val :=
  rec: "KVState__applyReadonly" "s" "args" :=
    (if: (SliceGet byteT "args" #0) ≠ OP_GET
    then Panic "expected a GET as readonly-operation"
    else #());;
    let: "key" := decodeGetArgs "args" in
    let: "reply" := KVState__get "s" "key" in
    let: ("vnum", "ok") := MapGet (struct.loadF KVState "vnums" "s") "key" in
    (if: "ok"
    then ("vnum", "reply")
    else (struct.loadF KVState "minVnum" "s", "reply")).

Definition KVState__getState: val :=
  rec: "KVState__getState" "s" :=
    map_string_marshal.EncodeStringMap (struct.loadF KVState "kvs" "s").

Definition KVState__setState: val :=
  rec: "KVState__setState" "s" "snap" "nextIndex" :=
    struct.storeF KVState "minVnum" "s" "nextIndex";;
    struct.storeF KVState "vnums" "s" (NewMap stringT uint64T #());;
    struct.storeF KVState "kvs" "s" (map_string_marshal.DecodeStringMap "snap");;
    #().

Definition makeVersionedStateMachine: val :=
  rec: "makeVersionedStateMachine" <> :=
    let: "s" := struct.alloc KVState (zero_val (struct.t KVState)) in
    struct.storeF KVState "kvs" "s" (NewMap stringT stringT #());;
    struct.storeF KVState "vnums" "s" (NewMap stringT uint64T #());;
    struct.new esm.VersionedStateMachine [
      "ApplyVolatile" ::= KVState__apply "s";
      "ApplyReadonly" ::= KVState__applyReadonly "s";
      "GetState" ::= (λ: <>,
        KVState__getState "s"
        );
      "SetState" ::= KVState__setState "s"
    ].

Definition Start: val :=
  rec: "Start" "fname" "host" "confHost" :=
    pb.Server__Serve (simplelog.MakePbServer (esm.MakeExactlyOnceStateMachine (makeVersionedStateMachine #())) "fname" "confHost") "host";;
    #().
