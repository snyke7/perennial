(* autogenerated from github.com/mit-pdos/gokv/dmvcc/index *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.go_mvcc.index.

Section code.
Context `{ext_ty: ext_types}.
Local Coercion Var' s: expr := Var s.

(* 0_server.go *)

Definition Server := struct.decl [
  "index" :: ptrT
].

Definition Server__AcquireTuple: val :=
  rec: "Server__AcquireTuple" "s" "key" "tid" :=
    tuple.Tuple__Own (index.Index__GetTuple (struct.loadF Server "index" "s") "key") "tid".

Definition Server__Read: val :=
  rec: "Server__Read" "s" "key" "tid" :=
    let: "t" := index.Index__GetTuple (struct.loadF Server "index" "s") "key" in
    tuple.Tuple__ReadWait "t" "tid";;
    let: ("val", <>) := tuple.Tuple__ReadVersion (index.Index__GetTuple (struct.loadF Server "index" "s") "key") "tid" in
    "val".

Definition Server__UpdateAndRelease: val :=
  rec: "Server__UpdateAndRelease" "s" "tid" "writes" :=
    MapIter "writes" (λ: "key" "val",
      let: "t" := index.Index__GetTuple (struct.loadF Server "index" "s") "key" in
      tuple.Tuple__WriteLock "t";;
      tuple.Tuple__AppendVersion "t" "tid" "val");;
    #().

Definition MakeServer: val :=
  rec: "MakeServer" <> :=
    struct.new Server [
      "index" ::= index.MkIndex #()
    ].

(* clerk.go *)

Definition Clerk := struct.decl [
  "s" :: ptrT
].

Definition Clerk__AcquireTuple: val :=
  rec: "Clerk__AcquireTuple" "ck" "key" "tid" :=
    Server__AcquireTuple (struct.loadF Clerk "s" "ck") "key" "tid".

Definition Clerk__Read: val :=
  rec: "Clerk__Read" "ck" "key" "tid" :=
    Server__Read (struct.loadF Clerk "s" "ck") "key" "tid".

Definition Clerk__UpdateAndRelease: val :=
  rec: "Clerk__UpdateAndRelease" "ck" "tid" "writes" :=
    Server__UpdateAndRelease (struct.loadF Clerk "s" "ck") "tid" "writes";;
    #().

Definition MakeClerk: val :=
  rec: "MakeClerk" "hostname" :=
    struct.new Clerk [
      "s" ::= "hostname"
    ].

End code.
