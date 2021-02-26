(* autogenerated from github.com/mit-pdos/lockservice/lockservice *)
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.grove_prelude.

From Goose Require github_com.mit_pdos.goose_nfsd.lockmap.
From Goose Require github_com.mit_pdos.lockservice.grove_common.
From Goose Require github_com.tchajed.marshal.

(* 0_common.go *)

Definition nondet: val :=
  rec: "nondet" <> :=
    #true.

(* Call this before doing an increment that has risk of overflowing.
   If it's going to overflow, this'll loop forever, so the bad addition can never happen *)
Definition overflow_guard_incr: val :=
  rec: "overflow_guard_incr" "v" :=
    Skip;;
    (for: (λ: <>, "v" + #1 < "v"); (λ: <>, Skip) := λ: <>,
      Continue).

(* 0_rpc.go *)

Definition RpcCoreHandler: ty := (struct.t grove_common.RPCVals.S -> uint64T)%ht.

Definition RpcCorePersister: ty := (unitT -> unitT)%ht.

Definition CheckReplyTable: val :=
  rec: "CheckReplyTable" "lastSeq" "lastReply" "CID" "Seq" "reply" :=
    let: ("last", "ok") := MapGet "lastSeq" "CID" in
    struct.storeF grove_common.RPCReply.S "Stale" "reply" #false;;
    (if: "ok" && ("Seq" ≤ "last")
    then
      (if: "Seq" < "last"
      then
        struct.storeF grove_common.RPCReply.S "Stale" "reply" #true;;
        #true
      else
        struct.storeF grove_common.RPCReply.S "Ret" "reply" (Fst (MapGet "lastReply" "CID"));;
        #true)
    else
      MapInsert "lastSeq" "CID" "Seq";;
      #false).

(* Emulate an RPC call over a lossy network.
   Returns true iff server reported error or request "timed out".
   For the "real thing", this should instead submit a request via the network. *)
Definition RemoteProcedureCall: val :=
  rec: "RemoteProcedureCall" "host" "rpcid" "req" "reply" :=
    Fork (let: "dummy_reply" := struct.alloc grove_common.RPCReply.S (zero_val (struct.t grove_common.RPCReply.S)) in
          Skip;;
          (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
            let: "rpc" := grove_ffi.GetServer "host" "rpcid" in
            "rpc" "req" "dummy_reply";;
            Continue));;
    (if: nondet #()
    then
      let: "rpc" := grove_ffi.GetServer "host" "rpcid" in
      "rpc" "req" "reply"
    else #true).

(* Common code for RPC clients: tracking of CID and next sequence number. *)
Module RPCClient.
  Definition S := struct.decl [
    "cid" :: uint64T;
    "seq" :: uint64T
  ].
End RPCClient.

Definition MakeRPCClient: val :=
  rec: "MakeRPCClient" "cid" :=
    struct.new RPCClient.S [
      "cid" ::= "cid";
      "seq" ::= #1
    ].

Definition RPCClient__MakeRequest: val :=
  rec: "RPCClient__MakeRequest" "cl" "host" "rpcid" "args" :=
    overflow_guard_incr (struct.loadF RPCClient.S "seq" "cl");;
    let: "req" := struct.new grove_common.RPCRequest.S [
      "Args" ::= "args";
      "CID" ::= struct.loadF RPCClient.S "cid" "cl";
      "Seq" ::= struct.loadF RPCClient.S "seq" "cl"
    ] in
    struct.storeF RPCClient.S "seq" "cl" (struct.loadF RPCClient.S "seq" "cl" + #1);;
    let: "errb" := ref_to boolT #false in
    let: "reply" := struct.alloc grove_common.RPCReply.S (zero_val (struct.t grove_common.RPCReply.S)) in
    Skip;;
    (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
      "errb" <-[boolT] RemoteProcedureCall "host" "rpcid" "req" "reply";;
      (if: (![boolT] "errb" = #false)
      then Break
      else Continue));;
    struct.loadF grove_common.RPCReply.S "Ret" "reply".

(* Common code for RPC servers: locking and handling of stale and redundant requests through
   the reply table. *)
Module RPCServer.
  Definition S := struct.decl [
    "mu" :: lockRefT;
    "lastSeq" :: mapT uint64T;
    "lastReply" :: mapT uint64T
  ].
End RPCServer.

Definition MakeRPCServer: val :=
  rec: "MakeRPCServer" <> :=
    let: "sv" := struct.alloc RPCServer.S (zero_val (struct.t RPCServer.S)) in
    struct.storeF RPCServer.S "lastSeq" "sv" (NewMap uint64T);;
    struct.storeF RPCServer.S "lastReply" "sv" (NewMap uint64T);;
    struct.storeF RPCServer.S "mu" "sv" (lock.new #());;
    "sv".

Definition RPCServer__HandleRequest: val :=
  rec: "RPCServer__HandleRequest" "sv" "core" "makeDurable" "req" "reply" :=
    lock.acquire (struct.loadF RPCServer.S "mu" "sv");;
    (if: CheckReplyTable (struct.loadF RPCServer.S "lastSeq" "sv") (struct.loadF RPCServer.S "lastReply" "sv") (struct.loadF grove_common.RPCRequest.S "CID" "req") (struct.loadF grove_common.RPCRequest.S "Seq" "req") "reply"
    then #()
    else
      struct.storeF grove_common.RPCReply.S "Ret" "reply" ("core" (struct.loadF grove_common.RPCRequest.S "Args" "req"));;
      MapInsert (struct.loadF RPCServer.S "lastReply" "sv") (struct.loadF grove_common.RPCRequest.S "CID" "req") (struct.loadF grove_common.RPCReply.S "Ret" "reply");;
      "makeDurable" #());;
    lock.release (struct.loadF RPCServer.S "mu" "sv");;
    #false.

(* 1_2pc.go *)

Module TxnResources.
  Definition S := struct.decl [
    "key" :: uint64T;
    "oldValue" :: uint64T
  ].
End TxnResources.

Module ParticipantServer.
  Definition S := struct.decl [
    "mu" :: lockRefT;
    "lockmap" :: struct.ptrT lockmap.LockMap.S;
    "kvs" :: mapT uint64T;
    "txns" :: mapT (struct.t TxnResources.S);
    "finishedTxns" :: mapT boolT
  ].
End ParticipantServer.

(* Precondition: emp
   returns 0 -> Vote Yes
   returns 1 -> Vote No *)
Definition ParticipantServer__PrepareIncrease: val :=
  rec: "ParticipantServer__PrepareIncrease" "ps" "tid" "key" "amount" :=
    lock.acquire (struct.loadF ParticipantServer.S "mu" "ps");;
    let: (<>, "ok") := MapGet (struct.loadF ParticipantServer.S "txns" "ps") "tid" in
    (if: "ok"
    then
      lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
      #0
    else
      let: (<>, "ok2") := MapGet (struct.loadF ParticipantServer.S "finishedTxns" "ps") "tid" in
      (if: "ok2"
      then
        lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
        #1
      else
        lockmap.LockMap__Acquire (struct.loadF ParticipantServer.S "lockmap" "ps") "key";;
        (if: "amount" + Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key") < Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key")
        then
          lockmap.LockMap__Release (struct.loadF ParticipantServer.S "lockmap" "ps") "key";;
          lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
          #1
        else
          MapInsert (struct.loadF ParticipantServer.S "txns" "ps") "tid" (struct.mk TxnResources.S [
            "key" ::= "key";
            "oldValue" ::= Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key")
          ]);;
          MapInsert (struct.loadF ParticipantServer.S "kvs" "ps") "key" (Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key") + "amount");;
          lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
          #0))).

Definition ParticipantServer__PrepareDecrease: val :=
  rec: "ParticipantServer__PrepareDecrease" "ps" "tid" "key" "amount" :=
    lock.acquire (struct.loadF ParticipantServer.S "mu" "ps");;
    let: (<>, "ok") := MapGet (struct.loadF ParticipantServer.S "txns" "ps") "tid" in
    (if: "ok"
    then
      lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
      #0
    else
      let: (<>, "ok2") := MapGet (struct.loadF ParticipantServer.S "finishedTxns" "ps") "tid" in
      (if: "ok2"
      then
        lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
        #1
      else
        lockmap.LockMap__Acquire (struct.loadF ParticipantServer.S "lockmap" "ps") "key";;
        (if: "amount" > Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key")
        then
          lockmap.LockMap__Release (struct.loadF ParticipantServer.S "lockmap" "ps") "key";;
          lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
          #1
        else
          MapInsert (struct.loadF ParticipantServer.S "txns" "ps") "tid" (struct.mk TxnResources.S [
            "key" ::= "key";
            "oldValue" ::= Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key")
          ]);;
          MapInsert (struct.loadF ParticipantServer.S "kvs" "ps") "key" (Fst (MapGet (struct.loadF ParticipantServer.S "kvs" "ps") "key") - "amount");;
          lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
          #0))).

Definition ParticipantServer__Commit: val :=
  rec: "ParticipantServer__Commit" "ps" "tid" :=
    lock.acquire (struct.loadF ParticipantServer.S "mu" "ps");;
    let: ("t", "ok") := MapGet (struct.loadF ParticipantServer.S "txns" "ps") "tid" in
    (if: ~ "ok"
    then
      lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
      #()
    else
      lockmap.LockMap__Release (struct.loadF ParticipantServer.S "lockmap" "ps") (struct.get TxnResources.S "key" "t");;
      MapDelete (struct.loadF ParticipantServer.S "txns" "ps") "tid";;
      MapInsert (struct.loadF ParticipantServer.S "finishedTxns" "ps") "tid" #true;;
      lock.release (struct.loadF ParticipantServer.S "mu" "ps")).

Definition ParticipantServer__Abort: val :=
  rec: "ParticipantServer__Abort" "ps" "tid" :=
    lock.acquire (struct.loadF ParticipantServer.S "mu" "ps");;
    let: ("t", "ok") := MapGet (struct.loadF ParticipantServer.S "txns" "ps") "tid" in
    (if: ~ "ok"
    then
      lock.release (struct.loadF ParticipantServer.S "mu" "ps");;
      #()
    else
      MapInsert (struct.loadF ParticipantServer.S "kvs" "ps") (struct.get TxnResources.S "key" "t") (struct.get TxnResources.S "oldValue" "t");;
      lockmap.LockMap__Release (struct.loadF ParticipantServer.S "lockmap" "ps") (struct.get TxnResources.S "key" "t");;
      MapDelete (struct.loadF ParticipantServer.S "txns" "ps") "tid";;
      MapInsert (struct.loadF ParticipantServer.S "finishedTxns" "ps") "tid" #true;;
      lock.release (struct.loadF ParticipantServer.S "mu" "ps")).

Definition MakeParticipantServer: val :=
  rec: "MakeParticipantServer" <> :=
    let: "s" := struct.alloc ParticipantServer.S (zero_val (struct.t ParticipantServer.S)) in
    struct.storeF ParticipantServer.S "mu" "s" (lock.new #());;
    struct.storeF ParticipantServer.S "lockmap" "s" (lockmap.MkLockMap #());;
    struct.storeF ParticipantServer.S "kvs" "s" (NewMap uint64T);;
    struct.storeF ParticipantServer.S "txns" "s" (NewMap (struct.t TxnResources.S));;
    struct.storeF ParticipantServer.S "finishedTxns" "s" (NewMap boolT).

Module TransactionCoordinator.
  Definition S := struct.decl [
    "s0" :: struct.ptrT ParticipantServer.S;
    "s1" :: struct.ptrT ParticipantServer.S
  ].
End TransactionCoordinator.

(* transfers between acc1 on s0 and acc2 on s1
   could also shard key-space *)
Definition TransactionCoordinator__doTransfer: val :=
  rec: "TransactionCoordinator__doTransfer" "tc" "tid" "acc1" "acc2" "amount" :=
    let: "prepared1" := ParticipantServer__PrepareIncrease (struct.loadF TransactionCoordinator.S "s0" "tc") "tid" "acc1" "amount" in
    let: "prepared2" := ParticipantServer__PrepareDecrease (struct.loadF TransactionCoordinator.S "s1" "tc") "tid" "acc2" "amount" in
    (if: ("prepared1" = #0) && ("prepared2" = #0)
    then
      ParticipantServer__Commit (struct.loadF TransactionCoordinator.S "s0" "tc") "tid";;
      ParticipantServer__Commit (struct.loadF TransactionCoordinator.S "s1" "tc") "tid"
    else
      ParticipantServer__Abort (struct.loadF TransactionCoordinator.S "s0" "tc") "tid";;
      ParticipantServer__Abort (struct.loadF TransactionCoordinator.S "s1" "tc") "tid").

(* 1_kvserver.go *)

Module KVServer.
  Definition S := struct.decl [
    "sv" :: struct.ptrT RPCServer.S;
    "kvs" :: mapT uint64T
  ].
End KVServer.

Definition KVServer__put_core: val :=
  rec: "KVServer__put_core" "ks" "args" :=
    MapInsert (struct.loadF KVServer.S "kvs" "ks") (struct.get grove_common.RPCVals.S "U64_1" "args") (struct.get grove_common.RPCVals.S "U64_2" "args");;
    #0.

Definition KVServer__get_core: val :=
  rec: "KVServer__get_core" "ks" "args" :=
    Fst (MapGet (struct.loadF KVServer.S "kvs" "ks") (struct.get grove_common.RPCVals.S "U64_1" "args")).

(* requires (2n + 1) uint64s worth of space in the encoder *)
Definition EncMap: val :=
  rec: "EncMap" "e" "m" :=
    marshal.Enc__PutInt "e" (MapLen "m");;
    MapIter "m" (λ: "key" "value",
      marshal.Enc__PutInt "e" "key";;
      marshal.Enc__PutInt "e" "value").

Definition DecMap: val :=
  rec: "DecMap" "d" :=
    let: "sz" := marshal.Dec__GetInt "d" in
    let: "m" := NewMap uint64T in
    let: "i" := ref_to uint64T #0 in
    Skip;;
    (for: (λ: <>, ![uint64T] "i" < "sz"); (λ: <>, Skip) := λ: <>,
      let: "k" := marshal.Dec__GetInt "d" in
      let: "v" := marshal.Dec__GetInt "d" in
      MapInsert "m" "k" "v";;
      "i" <-[uint64T] ![uint64T] "i" + #1;;
      Continue);;
    "m".

(* For now, there is only one kv server in the whole world
   Assume it's in file "kvdur" *)
Definition WriteDurableKVServer: val :=
  rec: "WriteDurableKVServer" "ks" :=
    let: "num_bytes" := #8 * #2 * MapLen (struct.loadF RPCServer.S "lastSeq" (struct.loadF KVServer.S "sv" "ks")) + #2 * MapLen (struct.loadF RPCServer.S "lastSeq" (struct.loadF KVServer.S "sv" "ks")) + #2 * MapLen (struct.loadF KVServer.S "kvs" "ks") + #3 in
    let: "e" := marshal.NewEnc "num_bytes" in
    EncMap "e" (struct.loadF RPCServer.S "lastSeq" (struct.loadF KVServer.S "sv" "ks"));;
    EncMap "e" (struct.loadF RPCServer.S "lastReply" (struct.loadF KVServer.S "sv" "ks"));;
    EncMap "e" (struct.loadF KVServer.S "kvs" "ks");;
    grove_ffi.Write #(str"kvdur") (marshal.Enc__Finish "e");;
    #().

Definition ReadDurableKVServer: val :=
  rec: "ReadDurableKVServer" <> :=
    let: "content" := grove_ffi.Read #(str"kvdur") in
    (if: (slice.len "content" = #0)
    then slice.nil
    else
      let: "d" := marshal.NewDec "content" in
      let: "ks" := struct.alloc KVServer.S (zero_val (struct.t KVServer.S)) in
      let: "sv" := struct.alloc RPCServer.S (zero_val (struct.t RPCServer.S)) in
      struct.storeF RPCServer.S "mu" "sv" (lock.new #());;
      struct.storeF RPCServer.S "lastSeq" "sv" (DecMap "d");;
      struct.storeF RPCServer.S "lastReply" "sv" (DecMap "d");;
      struct.storeF KVServer.S "kvs" "ks" (DecMap "d");;
      struct.storeF KVServer.S "sv" "ks" "sv";;
      "ks").

Definition KVServer__Put: val :=
  rec: "KVServer__Put" "ks" "req" "reply" :=
    RPCServer__HandleRequest (struct.loadF KVServer.S "sv" "ks") (λ: "args",
      KVServer__put_core "ks" "args"
      ) (λ: <>,
      WriteDurableKVServer "ks"
      ) "req" "reply".

Definition KVServer__Get: val :=
  rec: "KVServer__Get" "ks" "req" "reply" :=
    RPCServer__HandleRequest (struct.loadF KVServer.S "sv" "ks") (λ: "args",
      KVServer__get_core "ks" "args"
      ) (λ: <>,
      WriteDurableKVServer "ks"
      ) "req" "reply".

Definition MakeKVServer: val :=
  rec: "MakeKVServer" <> :=
    let: "ks_old" := ReadDurableKVServer #() in
    (if: "ks_old" ≠ #null
    then "ks_old"
    else
      let: "ks" := struct.alloc KVServer.S (zero_val (struct.t KVServer.S)) in
      struct.storeF KVServer.S "kvs" "ks" (NewMap uint64T);;
      struct.storeF KVServer.S "sv" "ks" (MakeRPCServer #());;
      "ks").

(* 1_lockserver.go *)

Module LockServer.
  Definition S := struct.decl [
    "sv" :: struct.ptrT RPCServer.S;
    "locks" :: mapT boolT
  ].
End LockServer.

Definition LockServer__tryLock_core: val :=
  rec: "LockServer__tryLock_core" "ls" "args" :=
    let: "lockname" := struct.get grove_common.RPCVals.S "U64_1" "args" in
    let: ("locked", <>) := MapGet (struct.loadF LockServer.S "locks" "ls") "lockname" in
    (if: "locked"
    then #0
    else
      MapInsert (struct.loadF LockServer.S "locks" "ls") "lockname" #true;;
      #1).

Definition LockServer__unlock_core: val :=
  rec: "LockServer__unlock_core" "ls" "args" :=
    let: "lockname" := struct.get grove_common.RPCVals.S "U64_1" "args" in
    let: ("locked", <>) := MapGet (struct.loadF LockServer.S "locks" "ls") "lockname" in
    (if: "locked"
    then
      MapInsert (struct.loadF LockServer.S "locks" "ls") "lockname" #false;;
      #1
    else #0).

(* For now, there is only one lock server in the whole world *)
Definition WriteDurableLockServer: val :=
  rec: "WriteDurableLockServer" "ks" :=
    #().

Definition ReadDurableLockServer: val :=
  rec: "ReadDurableLockServer" <> :=
    slice.nil.

(* server Lock RPC handler.
   returns true iff error *)
Definition LockServer__TryLock: val :=
  rec: "LockServer__TryLock" "ls" "req" "reply" :=
    let: "f" := (λ: "args",
      LockServer__tryLock_core "ls" "args"
      ) in
    let: "fdur" := (λ: <>,
      WriteDurableLockServer "ls"
      ) in
    let: "r" := RPCServer__HandleRequest (struct.loadF LockServer.S "sv" "ls") "f" "fdur" "req" "reply" in
    WriteDurableLockServer "ls";;
    "r".

(* server Unlock RPC handler.
   returns true iff error *)
Definition LockServer__Unlock: val :=
  rec: "LockServer__Unlock" "ls" "req" "reply" :=
    let: "f" := (λ: "args",
      LockServer__unlock_core "ls" "args"
      ) in
    let: "fdur" := (λ: <>,
      WriteDurableLockServer "ls"
      ) in
    let: "r" := RPCServer__HandleRequest (struct.loadF LockServer.S "sv" "ls") "f" "fdur" "req" "reply" in
    WriteDurableLockServer "ls";;
    "r".

Definition MakeLockServer: val :=
  rec: "MakeLockServer" <> :=
    let: "ls_old" := ReadDurableLockServer #() in
    (if: "ls_old" ≠ #null
    then "ls_old"
    else
      let: "ls" := struct.alloc LockServer.S (zero_val (struct.t LockServer.S)) in
      struct.storeF LockServer.S "locks" "ls" (NewMap boolT);;
      struct.storeF LockServer.S "sv" "ls" (MakeRPCServer #());;
      "ls").

(* 3_kvclient.go *)

(* the lockservice Clerk lives in the client
   and maintains a little state. *)
Module KVClerk.
  Definition S := struct.decl [
    "primary" :: uint64T;
    "client" :: struct.ptrT RPCClient.S;
    "cid" :: uint64T;
    "seq" :: uint64T
  ].
End KVClerk.

Definition KV_PUT : expr := #1.

Definition KV_GET : expr := #2.

Definition MakeKVClerk: val :=
  rec: "MakeKVClerk" "primary" "cid" :=
    let: "ck" := struct.alloc KVClerk.S (zero_val (struct.t KVClerk.S)) in
    struct.storeF KVClerk.S "primary" "ck" "primary";;
    struct.storeF KVClerk.S "client" "ck" (MakeRPCClient "cid");;
    "ck".

Definition KVClerk__Put: val :=
  rec: "KVClerk__Put" "ck" "key" "val" :=
    RPCClient__MakeRequest (struct.loadF KVClerk.S "client" "ck") (struct.loadF KVClerk.S "primary" "ck") KV_PUT (struct.mk grove_common.RPCVals.S [
      "U64_1" ::= "key";
      "U64_2" ::= "val"
    ]);;
    #().

Definition KVClerk__Get: val :=
  rec: "KVClerk__Get" "ck" "key" :=
    RPCClient__MakeRequest (struct.loadF KVClerk.S "client" "ck") (struct.loadF KVClerk.S "primary" "ck") KV_GET (struct.mk grove_common.RPCVals.S [
      "U64_1" ::= "key"
    ]).

(* 3_lockclient.go *)

(* the lockservice Clerk lives in the client
   and maintains a little state. *)
Module Clerk.
  Definition S := struct.decl [
    "primary" :: uint64T;
    "client" :: struct.ptrT RPCClient.S
  ].
End Clerk.

Definition LOCK_TRYLOCK : expr := #1.

Definition LOCK_UNLOCK : expr := #2.

Definition MakeClerk: val :=
  rec: "MakeClerk" "primary" "cid" :=
    let: "ck" := struct.alloc Clerk.S (zero_val (struct.t Clerk.S)) in
    struct.storeF Clerk.S "primary" "ck" "primary";;
    struct.storeF Clerk.S "client" "ck" (MakeRPCClient "cid");;
    "ck".

Definition Clerk__TryLock: val :=
  rec: "Clerk__TryLock" "ck" "lockname" :=
    RPCClient__MakeRequest (struct.loadF Clerk.S "client" "ck") (struct.loadF Clerk.S "primary" "ck") LOCK_TRYLOCK (struct.mk grove_common.RPCVals.S [
      "U64_1" ::= "lockname"
    ]) ≠ #0.

(* ask the lock service to unlock a lock.
   returns true if the lock was previously held,
   false otherwise. *)
Definition Clerk__Unlock: val :=
  rec: "Clerk__Unlock" "ck" "lockname" :=
    RPCClient__MakeRequest (struct.loadF Clerk.S "client" "ck") (struct.loadF Clerk.S "primary" "ck") LOCK_UNLOCK (struct.mk grove_common.RPCVals.S [
      "U64_1" ::= "lockname"
    ]) ≠ #0.

(* Spins until we have the lock *)
Definition Clerk__Lock: val :=
  rec: "Clerk__Lock" "ck" "lockname" :=
    Skip;;
    (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
      (if: Clerk__TryLock "ck" "lockname"
      then Break
      else Continue));;
    #true.

(* 4_bank.go *)

Module Bank.
  Definition S := struct.decl [
    "ls" :: uint64T;
    "ks" :: uint64T
  ].
End Bank.

Module BankClerk.
  Definition S := struct.decl [
    "lck" :: struct.ptrT Clerk.S;
    "kvck" :: struct.ptrT KVClerk.S;
    "acc1" :: uint64T;
    "acc2" :: uint64T
  ].
End BankClerk.

Definition acquire_two: val :=
  rec: "acquire_two" "lck" "l1" "l2" :=
    (if: "l1" < "l2"
    then
      Clerk__Lock "lck" "l1";;
      Clerk__Lock "lck" "l2"
    else
      Clerk__Lock "lck" "l2";;
      Clerk__Lock "lck" "l1");;
    #().

Definition release_two: val :=
  rec: "release_two" "lck" "l1" "l2" :=
    (if: "l1" < "l2"
    then
      Clerk__Unlock "lck" "l2";;
      Clerk__Unlock "lck" "l1"
    else
      Clerk__Unlock "lck" "l1";;
      Clerk__Unlock "lck" "l2");;
    #().

(* Requires that the account numbers are smaller than num_accounts
   If account balance in acc_from is at least amount, transfer amount to acc_to *)
Definition BankClerk__transfer_internal: val :=
  rec: "BankClerk__transfer_internal" "bck" "acc_from" "acc_to" "amount" :=
    acquire_two (struct.loadF BankClerk.S "lck" "bck") "acc_from" "acc_to";;
    let: "old_amount" := KVClerk__Get (struct.loadF BankClerk.S "kvck" "bck") "acc_from" in
    (if: "old_amount" ≥ "amount"
    then
      KVClerk__Put (struct.loadF BankClerk.S "kvck" "bck") "acc_from" ("old_amount" - "amount");;
      KVClerk__Put (struct.loadF BankClerk.S "kvck" "bck") "acc_to" (KVClerk__Get (struct.loadF BankClerk.S "kvck" "bck") "acc_to" + "amount");;
      #()
    else #());;
    release_two (struct.loadF BankClerk.S "lck" "bck") "acc_from" "acc_to".

Definition BankClerk__SimpleTransfer: val :=
  rec: "BankClerk__SimpleTransfer" "bck" "amount" :=
    BankClerk__transfer_internal "bck" (struct.loadF BankClerk.S "acc1" "bck") (struct.loadF BankClerk.S "acc2" "bck") "amount".

(* If account balance in acc_from is at least amount, transfer amount to acc_to *)
Definition BankClerk__SimpleAudit: val :=
  rec: "BankClerk__SimpleAudit" "bck" :=
    acquire_two (struct.loadF BankClerk.S "lck" "bck") (struct.loadF BankClerk.S "acc1" "bck") (struct.loadF BankClerk.S "acc2" "bck");;
    let: "sum" := KVClerk__Get (struct.loadF BankClerk.S "kvck" "bck") (struct.loadF BankClerk.S "acc1" "bck") + KVClerk__Get (struct.loadF BankClerk.S "kvck" "bck") (struct.loadF BankClerk.S "acc2" "bck") in
    release_two (struct.loadF BankClerk.S "lck" "bck") (struct.loadF BankClerk.S "acc1" "bck") (struct.loadF BankClerk.S "acc2" "bck");;
    "sum".

Definition MakeBank: val :=
  rec: "MakeBank" "acc" "balance" :=
    let: "ls" := MakeLockServer #() in
    let: "ks" := MakeKVServer #() in
    MapInsert (struct.loadF KVServer.S "kvs" "ks") "acc" "balance";;
    let: "ls_handlers" := NewMap grove_common.RpcFunc in
    MapInsert "ls_handlers" LOCK_TRYLOCK (LockServer__TryLock "ls");;
    MapInsert "ls_handlers" LOCK_UNLOCK (LockServer__Unlock "ls");;
    let: "lsid" := grove_ffi.AllocServer "ls_handlers" in
    let: "ks_handlers" := NewMap grove_common.RpcFunc in
    MapInsert "ks_handlers" KV_PUT (KVServer__Put "ks");;
    MapInsert "ks_handlers" KV_GET (KVServer__Get "ks");;
    let: "ksid" := grove_ffi.AllocServer "ks_handlers" in
    struct.mk Bank.S [
      "ls" ::= "lsid";
      "ks" ::= "ksid"
    ].

Definition MakeBankClerk: val :=
  rec: "MakeBankClerk" "b" "acc1" "acc2" "cid" :=
    let: "bck" := struct.alloc BankClerk.S (zero_val (struct.t BankClerk.S)) in
    struct.storeF BankClerk.S "lck" "bck" (MakeClerk (struct.get Bank.S "ls" "b") "cid");;
    struct.storeF BankClerk.S "kvck" "bck" (MakeKVClerk (struct.get Bank.S "ks" "b") "cid");;
    struct.storeF BankClerk.S "acc1" "bck" "acc1";;
    struct.storeF BankClerk.S "acc2" "bck" "acc2";;
    "bck".

(* 4_incrserver.go *)

Module IncrServer.
  Definition S := struct.decl [
    "sv" :: struct.ptrT RPCServer.S;
    "kvserver" :: struct.ptrT KVServer.S;
    "kck" :: struct.ptrT KVClerk.S
  ].
End IncrServer.

Definition IncrServer__increment_core_unsafe: val :=
  rec: "IncrServer__increment_core_unsafe" "is" "seq" "args" :=
    let: "key" := struct.get grove_common.RPCVals.S "U64_1" "args" in
    let: "oldv" := ref (zero_val uint64T) in
    "oldv" <-[uint64T] KVClerk__Get (struct.loadF IncrServer.S "kck" "is") "key";;
    KVClerk__Put (struct.loadF IncrServer.S "kck" "is") "key" (![uint64T] "oldv" + #1);;
    #0.

(* crash-safely increment counter and return the new value

   Idea is this:
   In the unsafe version, we ought to have the quadruples

   { key [kv]-> a }
    A
   { key [kv]-> _ \ast v = a }
   { key [kv]-> a }

   { key [kv]-> _ \ast v = a \ast durable_oldv = a }
    B
   { key [kv]-> (a + 1) }
   { key [kv]-> _ \ast durable_oldv = a }

   By adding code between A and B that makes durable_oldv = v, we can ensure
   that rerunning the function will result in B starting with the correct
   durable_oldv.
   TODO: test this
   Probably won't try proving this version correct (first). *)
Definition IncrServer__increment_core: val :=
  rec: "IncrServer__increment_core" "is" "seq" "args" :=
    let: "key" := struct.get grove_common.RPCVals.S "U64_1" "args" in
    let: "oldv" := ref (zero_val uint64T) in
    let: "filename" := #(str"incr_request_") + grove_ffi.U64ToString "seq" + #(str"_oldv") in
    let: "content" := grove_ffi.Read "filename" in
    (if: slice.len "content" > #0
    then "oldv" <-[uint64T] marshal.Dec__GetInt (marshal.NewDec (grove_ffi.Read "filename"))
    else
      "oldv" <-[uint64T] KVClerk__Get (struct.loadF IncrServer.S "kck" "is") "key";;
      let: "enc" := marshal.NewEnc #8 in
      marshal.Enc__PutInt "enc" (![uint64T] "oldv");;
      grove_ffi.Write "filename" (marshal.Enc__Finish "enc"));;
    KVClerk__Put (struct.loadF IncrServer.S "kck" "is") "key" (![uint64T] "oldv" + #1);;
    #0.

(* For now, there is only one kv server in the whole world *)
Definition WriteDurableIncrServer: val :=
  rec: "WriteDurableIncrServer" "ks" :=
    #().

Definition IncrServer__Increment: val :=
  rec: "IncrServer__Increment" "is" "req" "reply" :=
    lock.acquire (struct.loadF RPCServer.S "mu" (struct.loadF IncrServer.S "sv" "is"));;
    (if: CheckReplyTable (struct.loadF RPCServer.S "lastSeq" (struct.loadF IncrServer.S "sv" "is")) (struct.loadF RPCServer.S "lastReply" (struct.loadF IncrServer.S "sv" "is")) (struct.loadF grove_common.RPCRequest.S "CID" "req") (struct.loadF grove_common.RPCRequest.S "Seq" "req") "reply"
    then #()
    else
      struct.storeF grove_common.RPCReply.S "Ret" "reply" (IncrServer__increment_core "is" (struct.loadF grove_common.RPCRequest.S "Seq" "req") (struct.loadF grove_common.RPCRequest.S "Args" "req"));;
      MapInsert (struct.loadF RPCServer.S "lastReply" (struct.loadF IncrServer.S "sv" "is")) (struct.loadF grove_common.RPCRequest.S "CID" "req") (struct.loadF grove_common.RPCReply.S "Ret" "reply");;
      WriteDurableIncrServer "is");;
    lock.release (struct.loadF RPCServer.S "mu" (struct.loadF IncrServer.S "sv" "is"));;
    #false.

Definition ReadDurableIncrServer: val :=
  rec: "ReadDurableIncrServer" <> :=
    slice.nil.

Definition MakeIncrServer: val :=
  rec: "MakeIncrServer" "kvserver" :=
    let: "is_old" := ReadDurableIncrServer #() in
    (if: "is_old" ≠ #null
    then "is_old"
    else
      let: "is" := struct.alloc IncrServer.S (zero_val (struct.t IncrServer.S)) in
      struct.storeF IncrServer.S "sv" "is" (MakeRPCServer #());;
      struct.storeF IncrServer.S "kvserver" "is" "kvserver";;
      "is").

(* 5_incrclient.go *)

Module IncrClerk.
  Definition S := struct.decl [
    "primary" :: uint64T;
    "client" :: struct.ptrT RPCClient.S;
    "cid" :: uint64T;
    "seq" :: uint64T
  ].
End IncrClerk.

Definition INCR_INCREMENT : expr := #1.

Definition MakeIncrClerk: val :=
  rec: "MakeIncrClerk" "primary" "cid" :=
    let: "ck" := struct.alloc IncrClerk.S (zero_val (struct.t IncrClerk.S)) in
    struct.storeF IncrClerk.S "primary" "ck" "primary";;
    struct.storeF IncrClerk.S "client" "ck" (MakeRPCClient "cid");;
    "ck".

Definition IncrClerk__Increment: val :=
  rec: "IncrClerk__Increment" "ck" "key" :=
    RPCClient__MakeRequest (struct.loadF IncrClerk.S "client" "ck") (struct.loadF IncrClerk.S "primary" "ck") INCR_INCREMENT (struct.mk grove_common.RPCVals.S [
      "U64_1" ::= "key"
    ]);;
    #().

(* 6_incrproxyserver.go *)

Module IncrProxyServer.
  Definition S := struct.decl [
    "sv" :: struct.ptrT RPCServer.S;
    "incrserver" :: uint64T;
    "ick" :: struct.ptrT IncrClerk.S;
    "lastCID" :: uint64T
  ].
End IncrProxyServer.

Definition IncrProxyServer__proxy_increment_core_unsafe: val :=
  rec: "IncrProxyServer__proxy_increment_core_unsafe" "is" "seq" "args" :=
    let: "key" := struct.get grove_common.RPCVals.S "U64_1" "args" in
    IncrClerk__Increment (struct.loadF IncrProxyServer.S "ick" "is") "key";;
    #0.

(* Common code for RPC clients: tracking of CID and next sequence number. *)
Module ShortTermIncrClerk.
  Definition S := struct.decl [
    "cid" :: uint64T;
    "seq" :: uint64T;
    "req" :: struct.t grove_common.RPCRequest.S;
    "incrserver" :: uint64T
  ].
End ShortTermIncrClerk.

Definition ShortTermIncrClerk__PrepareRequest: val :=
  rec: "ShortTermIncrClerk__PrepareRequest" "ck" "args" :=
    overflow_guard_incr (struct.loadF ShortTermIncrClerk.S "seq" "ck");;
    struct.storeF ShortTermIncrClerk.S "req" "ck" (struct.mk grove_common.RPCRequest.S [
      "Args" ::= "args";
      "CID" ::= struct.loadF ShortTermIncrClerk.S "cid" "ck";
      "Seq" ::= struct.loadF ShortTermIncrClerk.S "seq" "ck"
    ]);;
    struct.storeF ShortTermIncrClerk.S "seq" "ck" (struct.loadF ShortTermIncrClerk.S "seq" "ck" + #1).

Definition ShortTermIncrClerk__MakePreparedRequest: val :=
  rec: "ShortTermIncrClerk__MakePreparedRequest" "ck" :=
    let: "errb" := ref_to boolT #false in
    let: "reply" := struct.alloc grove_common.RPCReply.S (zero_val (struct.t grove_common.RPCReply.S)) in
    Skip;;
    (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
      "errb" <-[boolT] RemoteProcedureCall (struct.loadF ShortTermIncrClerk.S "incrserver" "ck") INCR_INCREMENT (struct.fieldRef ShortTermIncrClerk.S "req" "ck") "reply";;
      (if: (![boolT] "errb" = #false)
      then Break
      else Continue));;
    struct.loadF grove_common.RPCReply.S "Ret" "reply".

Definition DecodeShortTermIncrClerk: val :=
  rec: "DecodeShortTermIncrClerk" "is" "content" :=
    let: "d" := marshal.NewDec "content" in
    let: "ck" := struct.alloc ShortTermIncrClerk.S (zero_val (struct.t ShortTermIncrClerk.S)) in
    struct.storeF ShortTermIncrClerk.S "incrserver" "ck" "is";;
    struct.storeF ShortTermIncrClerk.S "cid" "ck" (marshal.Dec__GetInt "d");;
    struct.storeF ShortTermIncrClerk.S "seq" "ck" (marshal.Dec__GetInt "d");;
    struct.storeF grove_common.RPCRequest.S "CID" (struct.fieldRef ShortTermIncrClerk.S "req" "ck") (struct.loadF ShortTermIncrClerk.S "cid" "ck");;
    struct.storeF grove_common.RPCRequest.S "Seq" (struct.fieldRef ShortTermIncrClerk.S "req" "ck") (struct.loadF ShortTermIncrClerk.S "seq" "ck" - #1);;
    struct.storeF grove_common.RPCVals.S "U64_1" (struct.fieldRef grove_common.RPCRequest.S "Args" (struct.fieldRef ShortTermIncrClerk.S "req" "ck")) (marshal.Dec__GetInt "d");;
    struct.storeF grove_common.RPCVals.S "U64_2" (struct.fieldRef grove_common.RPCRequest.S "Args" (struct.fieldRef ShortTermIncrClerk.S "req" "ck")) (marshal.Dec__GetInt "d");;
    "ck".

Definition EncodeShortTermIncrClerk: val :=
  rec: "EncodeShortTermIncrClerk" "ck" :=
    let: "e" := marshal.NewEnc #32 in
    marshal.Enc__PutInt "e" (struct.loadF ShortTermIncrClerk.S "cid" "ck");;
    marshal.Enc__PutInt "e" (struct.loadF ShortTermIncrClerk.S "seq" "ck");;
    marshal.Enc__PutInt "e" (struct.get grove_common.RPCVals.S "U64_1" (struct.get grove_common.RPCRequest.S "Args" (struct.loadF ShortTermIncrClerk.S "req" "ck")));;
    marshal.Enc__PutInt "e" (struct.get grove_common.RPCVals.S "U64_2" (struct.get grove_common.RPCRequest.S "Args" (struct.loadF ShortTermIncrClerk.S "req" "ck")));;
    marshal.Enc__Finish "e".

Definition IncrProxyServer__MakeFreshIncrClerk: val :=
  rec: "IncrProxyServer__MakeFreshIncrClerk" "is" :=
    let: "cid" := struct.loadF IncrProxyServer.S "lastCID" "is" in
    overflow_guard_incr (struct.loadF IncrProxyServer.S "lastCID" "is");;
    struct.storeF IncrProxyServer.S "lastCID" "is" (struct.loadF IncrProxyServer.S "lastCID" "is" + #1);;
    let: "e" := marshal.NewEnc #8 in
    marshal.Enc__PutInt "e" (struct.loadF IncrProxyServer.S "lastCID" "is");;
    grove_ffi.Write #(str"lastCID") (marshal.Enc__Finish "e");;
    let: "ck_ptr" := struct.alloc ShortTermIncrClerk.S (zero_val (struct.t ShortTermIncrClerk.S)) in
    struct.storeF ShortTermIncrClerk.S "cid" "ck_ptr" "cid";;
    struct.storeF ShortTermIncrClerk.S "seq" "ck_ptr" #1;;
    struct.storeF ShortTermIncrClerk.S "incrserver" "ck_ptr" (struct.loadF IncrProxyServer.S "incrserver" "is");;
    "ck_ptr".

Definition IncrProxyServer__proxy_increment_core: val :=
  rec: "IncrProxyServer__proxy_increment_core" "is" "seq" "args" :=
    let: "filename" := #(str"procy_incr_request_") + grove_ffi.U64ToString "seq" in
    let: "ck" := ref (zero_val (refT (struct.t ShortTermIncrClerk.S))) in
    let: "content" := grove_ffi.Read "filename" in
    (if: slice.len "content" > #0
    then "ck" <-[refT (struct.t ShortTermIncrClerk.S)] DecodeShortTermIncrClerk (struct.loadF IncrProxyServer.S "incrserver" "is") "content"
    else
      "ck" <-[refT (struct.t ShortTermIncrClerk.S)] IncrProxyServer__MakeFreshIncrClerk "is";;
      ShortTermIncrClerk__PrepareRequest (![refT (struct.t ShortTermIncrClerk.S)] "ck") "args";;
      let: "content" := EncodeShortTermIncrClerk (![refT (struct.t ShortTermIncrClerk.S)] "ck") in
      grove_ffi.Write "filename" "content");;
    ShortTermIncrClerk__MakePreparedRequest (![refT (struct.t ShortTermIncrClerk.S)] "ck");;
    #0.
