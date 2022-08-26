(* autogenerated from github.com/mit-pdos/gokv/simplepb/config *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.gokv.simplepb.e.
From Goose Require github_com.mit_pdos.gokv.urpc.
From Goose Require github_com.tchajed.marshal.

From Perennial.goose_lang Require Import ffi.grove_prelude.

(* 0_marshal.go *)

Definition EncodeConfig: val :=
  rec: "EncodeConfig" "config" :=
    let: "enc" := ref_to (slice.T byteT) (NewSliceWithCap byteT #0 (#8 + #8 * slice.len "config")) in
    "enc" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "enc") (slice.len "config");;
    ForSlice uint64T <> "h" "config"
      ("enc" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "enc") "h");;
    ![slice.T byteT] "enc".

Definition DecodeConfig: val :=
  rec: "DecodeConfig" "enc_config" :=
    let: "enc" := ref_to (slice.T byteT) "enc_config" in
    let: "configLen" := ref (zero_val uint64T) in
    let: ("0_ret", "1_ret") := marshal.ReadInt (![slice.T byteT] "enc") in
    "configLen" <-[uint64T] "0_ret";;
    "enc" <-[slice.T byteT] "1_ret";;
    let: "config" := NewSlice uint64T (![uint64T] "configLen") in
    let: "i" := ref_to uint64T #0 in
    Skip;;
    (for: (λ: <>, ![uint64T] "i" < slice.len "config"); (λ: <>, Skip) := λ: <>,
      let: ("0_ret", "1_ret") := marshal.ReadInt (![slice.T byteT] "enc") in
      SliceSet uint64T "config" (![uint64T] "i") "0_ret";;
      "enc" <-[slice.T byteT] "1_ret";;
      "i" <-[uint64T] ![uint64T] "i" + #1;;
      Continue);;
    "config".

(* client.go *)

Definition Clerk := struct.decl [
  "cl" :: ptrT
].

Definition RPC_GETEPOCH : expr := #0.

Definition RPC_GETCONFIG : expr := #1.

Definition RPC_WRITECONFIG : expr := #2.

Definition MakeClerk: val :=
  rec: "MakeClerk" "host" :=
    struct.new Clerk [
      "cl" ::= urpc.MakeClient "host"
    ].

Definition Clerk__GetEpochAndConfig: val :=
  rec: "Clerk__GetEpochAndConfig" "ck" :=
    let: "reply" := ref (zero_val (slice.T byteT)) in
    Skip;;
    (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
      let: "err" := urpc.Client__Call (struct.loadF Clerk "cl" "ck") RPC_GETEPOCH (NewSlice byteT #0) "reply" #100 in
      (if: ("err" = #0)
      then Break
      else Continue));;
    let: "epoch" := ref (zero_val uint64T) in
    let: ("0_ret", "1_ret") := marshal.ReadInt (![slice.T byteT] "reply") in
    "epoch" <-[uint64T] "0_ret";;
    "reply" <-[slice.T byteT] "1_ret";;
    let: "config" := DecodeConfig (![slice.T byteT] "reply") in
    (![uint64T] "epoch", "config").

Definition Clerk__GetConfig: val :=
  rec: "Clerk__GetConfig" "ck" :=
    let: "reply" := ref (zero_val (slice.T byteT)) in
    Skip;;
    (for: (λ: <>, #true); (λ: <>, Skip) := λ: <>,
      let: "err" := urpc.Client__Call (struct.loadF Clerk "cl" "ck") RPC_GETCONFIG (NewSlice byteT #0) "reply" #100 in
      (if: ("err" = #0)
      then Break
      else Continue));;
    let: "config" := DecodeConfig (![slice.T byteT] "reply") in
    "config".

Definition Clerk__WriteConfig: val :=
  rec: "Clerk__WriteConfig" "ck" "epoch" "config" :=
    let: "reply" := ref (zero_val (slice.T byteT)) in
    let: "args" := ref_to (slice.T byteT) (NewSliceWithCap byteT #0 (#8 + #8 * slice.len "config")) in
    "args" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "args") "epoch";;
    "args" <-[slice.T byteT] marshal.WriteBytes (![slice.T byteT] "args") (EncodeConfig "config");;
    let: "err" := urpc.Client__Call (struct.loadF Clerk "cl" "ck") RPC_WRITECONFIG (![slice.T byteT] "args") "reply" #100 in
    (if: ("err" = #0)
    then
      let: ("e", <>) := marshal.ReadInt (![slice.T byteT] "reply") in
      "e"
    else "err").

(* server.go *)

Definition Server := struct.decl [
  "mu" :: ptrT;
  "epoch" :: uint64T;
  "config" :: slice.T uint64T
].

Definition Server__GetEpochAndConfig: val :=
  rec: "Server__GetEpochAndConfig" "s" "args" "reply" :=
    lock.acquire (struct.loadF Server "mu" "s");;
    struct.storeF Server "epoch" "s" (struct.loadF Server "epoch" "s" + #1);;
    "reply" <-[slice.T byteT] NewSliceWithCap byteT #0 (#8 + #8 * slice.len (struct.loadF Server "config" "s"));;
    "reply" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "reply") (struct.loadF Server "epoch" "s");;
    "reply" <-[slice.T byteT] marshal.WriteBytes (![slice.T byteT] "reply") (EncodeConfig (struct.loadF Server "config" "s"));;
    lock.release (struct.loadF Server "mu" "s");;
    #().

Definition Server__GetConfig: val :=
  rec: "Server__GetConfig" "s" "args" "reply" :=
    lock.acquire (struct.loadF Server "mu" "s");;
    "reply" <-[slice.T byteT] EncodeConfig (struct.loadF Server "config" "s");;
    lock.release (struct.loadF Server "mu" "s");;
    #().

Definition Server__WriteConfig: val :=
  rec: "Server__WriteConfig" "s" "args" "reply" :=
    lock.acquire (struct.loadF Server "mu" "s");;
    let: ("epoch", "enc") := marshal.ReadInt "args" in
    (if: "epoch" < struct.loadF Server "epoch" "s"
    then
      "reply" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "reply") e.Stale;;
      lock.release (struct.loadF Server "mu" "s");;
      (* log.Println("Stale write", s.config) *)
      #()
    else
      struct.storeF Server "config" "s" (DecodeConfig "enc");;
      (* log.Println("New config is:", s.config) *)
      "reply" <-[slice.T byteT] marshal.WriteInt (![slice.T byteT] "reply") e.None;;
      lock.release (struct.loadF Server "mu" "s");;
      #()).

Definition MakeServer: val :=
  rec: "MakeServer" <> :=
    let: "s" := struct.alloc Server (zero_val (struct.t Server)) in
    struct.storeF Server "mu" "s" (lock.new #());;
    struct.storeF Server "epoch" "s" #0;;
    struct.storeF Server "config" "s" (NewSlice uint64T #0);;
    "s".

Definition Server__Serve: val :=
  rec: "Server__Serve" "s" "me" :=
    let: "handlers" := NewMap ((slice.T byteT -> ptrT -> unitT)%ht) #() in
    MapInsert "handlers" RPC_GETEPOCH (Server__GetEpochAndConfig "s");;
    MapInsert "handlers" RPC_GETCONFIG (Server__GetConfig "s");;
    MapInsert "handlers" RPC_WRITECONFIG (Server__WriteConfig "s");;
    let: "rs" := urpc.MakeServer "handlers" in
    urpc.Server__Serve "rs" "me";;
    #().
