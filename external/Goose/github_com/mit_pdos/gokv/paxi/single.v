(* autogenerated from github.com/mit-pdos/gokv/paxi/single *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.gokv.urpc.

From Perennial.goose_lang Require Import ffi.grove_prelude.

(* clerk.go *)

Definition Clerk := struct.decl [
  "cl" :: ptrT
].

Definition MakeClerk: val :=
  rec: "MakeClerk" "host" :=
    struct.new Clerk [
      "cl" ::= urpc.MakeClient "host"
    ].

Definition Clerk__Prepare: val :=
  rec: "Clerk__Prepare" "ck" "pn" "reply" :=
    #().

Definition Clerk__Propose: val :=
  rec: "Clerk__Propose" "ck" "Pn" "Val" :=
    #false.

(* common.go *)

Definition ValType: ty := uint64T.

Definition PREPARE : expr := #1.

Definition PROPOSE : expr := #2.

(* singleslot.go *)

(* This isn't quite paxos *)
Definition Replica := struct.decl [
  "mu" :: ptrT;
  "promisedPN" :: uint64T;
  "acceptedPN" :: uint64T;
  "acceptedVal" :: ValType;
  "committedVal" :: ValType;
  "peers" :: slice.T ptrT
].

Definition PrepareReply := struct.decl [
  "Success" :: boolT;
  "Val" :: uint64T;
  "Pn" :: uint64T
].

Definition Replica__PrepareRPC: val :=
  rec: "Replica__PrepareRPC" "r" "pn" "reply" :=
    lock.acquire (struct.loadF Replica "mu" "r");;
    (if: "pn" > (struct.loadF Replica "promisedPN" "r")
    then
      struct.storeF Replica "promisedPN" "r" "pn";;
      struct.storeF PrepareReply "Pn" "reply" (struct.loadF Replica "acceptedPN" "r");;
      struct.storeF PrepareReply "Val" "reply" (struct.loadF Replica "acceptedVal" "r");;
      struct.storeF PrepareReply "Success" "reply" #true
    else
      struct.storeF PrepareReply "Success" "reply" #false;;
      struct.storeF PrepareReply "Pn" "reply" (struct.loadF Replica "promisedPN" "r"));;
    lock.release (struct.loadF Replica "mu" "r");;
    #().

Definition ProposeArgs := struct.decl [
  "Pn" :: uint64T;
  "Val" :: ValType
].

Definition Replica__ProposeRPC: val :=
  rec: "Replica__ProposeRPC" "r" "pn" "val" :=
    lock.acquire (struct.loadF Replica "mu" "r");;
    (if: ("pn" ≥ (struct.loadF Replica "promisedPN" "r")) && ("pn" ≥ (struct.loadF Replica "acceptedPN" "r"))
    then
      struct.storeF Replica "acceptedVal" "r" "val";;
      struct.storeF Replica "acceptedPN" "r" "pn";;
      lock.release (struct.loadF Replica "mu" "r");;
      #true
    else
      lock.release (struct.loadF Replica "mu" "r");;
      #false).

(* returns true iff there was an error *)
Definition Replica__TryDecide: val :=
  rec: "Replica__TryDecide" "r" "v" "outv" :=
    lock.acquire (struct.loadF Replica "mu" "r");;
    let: "pn" := (struct.loadF Replica "promisedPN" "r") + #1 in
    lock.release (struct.loadF Replica "mu" "r");;
    let: "numPrepared" := ref (zero_val uint64T) in
    "numPrepared" <-[uint64T] #0;;
    let: "highestPn" := ref (zero_val uint64T) in
    "highestPn" <-[uint64T] #0;;
    let: "highestVal" := ref (zero_val uint64T) in
    "highestVal" <-[uint64T] "v";;
    let: "mu" := lock.new #() in
    ForSlice ptrT <> "peer" (struct.loadF Replica "peers" "r")
      (let: "local_peer" := "peer" in
      Fork (let: "reply_ptr" := struct.alloc PrepareReply (zero_val (struct.t PrepareReply)) in
            Clerk__Prepare "local_peer" "pn" "reply_ptr";;
            (if: struct.loadF PrepareReply "Success" "reply_ptr"
            then
              lock.acquire "mu";;
              "numPrepared" <-[uint64T] ((![uint64T] "numPrepared") + #1);;
              (if: (struct.loadF PrepareReply "Pn" "reply_ptr") > (![uint64T] "highestPn")
              then
                "highestVal" <-[uint64T] (struct.loadF PrepareReply "Val" "reply_ptr");;
                "highestPn" <-[uint64T] (struct.loadF PrepareReply "Pn" "reply_ptr")
              else #());;
              lock.release "mu"
            else #())));;
    lock.acquire "mu";;
    let: "n" := ![uint64T] "numPrepared" in
    let: "proposeVal" := ![uint64T] "highestVal" in
    lock.release "mu";;
    (if: (#2 * "n") > (slice.len (struct.loadF Replica "peers" "r"))
    then
      let: "mu2" := lock.new #() in
      let: "numAccepted" := ref (zero_val uint64T) in
      "numAccepted" <-[uint64T] #0;;
      ForSlice ptrT <> "peer" (struct.loadF Replica "peers" "r")
        (let: "local_peer" := "peer" in
        Fork (let: "r" := Clerk__Propose "local_peer" "pn" "proposeVal" in
              (if: "r"
              then
                lock.acquire "mu2";;
                "numAccepted" <-[uint64T] ((![uint64T] "numAccepted") + #1);;
                lock.release "mu2"
              else #())));;
      lock.acquire "mu2";;
      let: "n" := ![uint64T] "numAccepted" in
      lock.release "mu2";;
      (if: (#2 * "n") > (slice.len (struct.loadF Replica "peers" "r"))
      then
        "outv" <-[uint64T] "proposeVal";;
        #false
      else #true)
    else #true).
