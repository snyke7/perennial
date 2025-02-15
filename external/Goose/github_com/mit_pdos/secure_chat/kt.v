(* autogenerated from github.com/mit-pdos/secure-chat/kt *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.gokv.urpc.
From Goose Require github_com.mit_pdos.secure_chat.kt.kt_shim.
From Goose Require github_com.mit_pdos.secure_chat.kt.shared.

From Perennial.goose_lang Require Import ffi.grove_prelude.

Definition keyServ := struct.decl [
  "mu" :: ptrT;
  "log" :: ptrT
].

Definition newKeyServ: val :=
  rec: "newKeyServ" <> :=
    struct.new keyServ [
      "mu" ::= lock.new #();
      "log" ::= shared.NewKeyLog #()
    ].

Definition keyServ__appendLog: val :=
  rec: "keyServ__appendLog" "ks" "entry" :=
    lock.acquire (struct.loadF keyServ "mu" "ks");;
    shared.KeyLog__Append (struct.loadF keyServ "log" "ks") "entry";;
    let: "outLog" := shared.KeyLog__DeepCopy (struct.loadF keyServ "log" "ks") in
    lock.release (struct.loadF keyServ "mu" "ks");;
    "outLog".

Definition keyServ__getLog: val :=
  rec: "keyServ__getLog" "ks" :=
    lock.acquire (struct.loadF keyServ "mu" "ks");;
    let: "outLog" := shared.KeyLog__DeepCopy (struct.loadF keyServ "log" "ks") in
    lock.release (struct.loadF keyServ "mu" "ks");;
    "outLog".

Definition keyServ__start: val :=
  rec: "keyServ__start" "ks" "me" :=
    let: "handlers" := NewMap uint64T ((slice.T byteT) -> ptrT -> unitT)%ht #() in
    MapInsert "handlers" shared.RpcAppendLog (λ: "enc_args" "enc_reply",
      let: "entry" := struct.alloc shared.UnameKey (zero_val (struct.t shared.UnameKey)) in
      let: (<>, "err") := shared.UnameKey__Decode "entry" "enc_args" in
      (if: "err" ≠ shared.ErrNone
      then #()
      else
        "enc_reply" <-[slice.T byteT] (shared.KeyLog__Encode (keyServ__appendLog "ks" "entry"));;
        #())
      );;
    MapInsert "handlers" shared.RpcGetLog (λ: "enc_args" "enc_reply",
      "enc_reply" <-[slice.T byteT] (shared.KeyLog__Encode (keyServ__getLog "ks"));;
      #()
      );;
    urpc.Server__Serve (urpc.MakeServer "handlers") "me";;
    #().

Definition checkLogIn := struct.decl [
  "currLog" :: ptrT;
  "newLogB" :: slice.T byteT;
  "uname" :: uint64T;
  "doLookup" :: boolT
].

Definition checkLogOut := struct.decl [
  "newLog" :: ptrT;
  "epoch" :: uint64T;
  "key" :: slice.T byteT;
  "err" :: uint64T
].

Definition errNewLogOut: val :=
  rec: "errNewLogOut" "err" :=
    struct.new checkLogOut [
      "newLog" ::= slice.nil;
      "epoch" ::= #0;
      "key" ::= slice.nil;
      "err" ::= "err"
    ].

(* Decode RPC ret, check log prefix, check key lookup. *)
Definition checkLog: val :=
  rec: "checkLog" "in" :=
    let: "newLog" := struct.alloc shared.KeyLog (zero_val (struct.t shared.KeyLog)) in
    let: (<>, "err1") := shared.KeyLog__Decode "newLog" (struct.loadF checkLogIn "newLogB" "in") in
    (if: "err1" ≠ shared.ErrNone
    then errNewLogOut "err1"
    else
      (if: (~ (shared.KeyLog__IsPrefix (struct.loadF checkLogIn "currLog" "in") "newLog"))
      then errNewLogOut shared.ErrKeyCli_CheckLogPrefix
      else
        (if: (~ (struct.loadF checkLogIn "doLookup" "in"))
        then
          struct.new checkLogOut [
            "newLog" ::= "newLog";
            "epoch" ::= #0;
            "key" ::= slice.nil;
            "err" ::= shared.ErrNone
          ]
        else
          let: (("epoch", "key"), "ok") := shared.KeyLog__Lookup "newLog" (struct.loadF checkLogIn "uname" "in") in
          (if: (~ "ok")
          then errNewLogOut shared.ErrKeyCli_CheckLogLookup
          else
            struct.new checkLogOut [
              "newLog" ::= "newLog";
              "epoch" ::= "epoch";
              "key" ::= "key";
              "err" ::= shared.ErrNone
            ])))).

Definition auditor := struct.decl [
  "mu" :: ptrT;
  "log" :: ptrT;
  "serv" :: ptrT;
  "key" :: ptrT
].

Definition newAuditor: val :=
  rec: "newAuditor" "servAddr" "key" :=
    let: "l" := shared.NewKeyLog #() in
    let: "c" := urpc.MakeClient "servAddr" in
    struct.new auditor [
      "mu" ::= lock.new #();
      "log" ::= "l";
      "serv" ::= "c";
      "key" ::= "key"
    ].

Definition auditor__doAudit: val :=
  rec: "auditor__doAudit" "a" :=
    lock.acquire (struct.loadF auditor "mu" "a");;
    let: "newLogB" := NewSlice byteT #0 in
    let: "err1" := urpc.Client__Call (struct.loadF auditor "serv" "a") shared.RpcGetLog slice.nil "newLogB" #100 in
    control.impl.Assume ("err1" = urpc.ErrNone);;
    let: "in" := struct.new checkLogIn [
      "currLog" ::= struct.loadF auditor "log" "a";
      "newLogB" ::= "newLogB";
      "uname" ::= #0;
      "doLookup" ::= #false
    ] in
    let: "out" := checkLog "in" in
    (if: (struct.loadF checkLogOut "err" "out") ≠ shared.ErrNone
    then
      lock.release (struct.loadF auditor "mu" "a");;
      struct.loadF checkLogOut "err" "out"
    else
      struct.storeF auditor "log" "a" (struct.loadF checkLogOut "newLog" "out");;
      lock.release (struct.loadF auditor "mu" "a");;
      shared.ErrNone).

Definition auditor__getAudit: val :=
  rec: "auditor__getAudit" "a" :=
    lock.acquire (struct.loadF auditor "mu" "a");;
    let: "logCopy" := shared.KeyLog__DeepCopy (struct.loadF auditor "log" "a") in
    let: "logB" := shared.KeyLog__Encode "logCopy" in
    let: "sig" := kt_shim.SignerT__Sign (struct.loadF auditor "key" "a") "logB" in
    lock.release (struct.loadF auditor "mu" "a");;
    struct.new shared.SigLog [
      "Sig" ::= "sig";
      "Log" ::= "logCopy"
    ].

Definition auditor__start: val :=
  rec: "auditor__start" "a" "me" :=
    let: "handlers" := NewMap uint64T ((slice.T byteT) -> ptrT -> unitT)%ht #() in
    MapInsert "handlers" shared.RpcDoAudit (λ: "enc_args" "enc_reply",
      let: "err" := auditor__doAudit "a" in
      control.impl.Assume ("err" = shared.ErrNone);;
      #()
      );;
    MapInsert "handlers" shared.RpcGetAudit (λ: "enc_args" "enc_reply",
      "enc_reply" <-[slice.T byteT] (shared.SigLog__Encode (auditor__getAudit "a"));;
      #()
      );;
    urpc.Server__Serve (urpc.MakeServer "handlers") "me";;
    #().

Definition keyCli := struct.decl [
  "log" :: ptrT;
  "serv" :: ptrT;
  "adtrs" :: slice.T ptrT;
  "adtrKeys" :: slice.T ptrT
].

Definition newKeyCli: val :=
  rec: "newKeyCli" "serv" "adtrs" "adtrKeys" :=
    let: "l" := shared.NewKeyLog #() in
    let: "servC" := urpc.MakeClient "serv" in
    let: "adtrsC" := NewSlice ptrT (slice.len "adtrs") in
    ForSlice uint64T "i" "addr" "adtrs"
      (SliceSet ptrT "adtrsC" "i" (urpc.MakeClient "addr"));;
    struct.new keyCli [
      "log" ::= "l";
      "serv" ::= "servC";
      "adtrs" ::= "adtrsC";
      "adtrKeys" ::= "adtrKeys"
    ].

Definition keyCli__register: val :=
  rec: "keyCli__register" "kc" "entry" :=
    let: "entryB" := shared.UnameKey__Encode "entry" in
    let: "newLogB" := NewSlice byteT #0 in
    let: "err1" := urpc.Client__Call (struct.loadF keyCli "serv" "kc") shared.RpcAppendLog "entryB" "newLogB" #100 in
    control.impl.Assume ("err1" = urpc.ErrNone);;
    let: "in" := struct.new checkLogIn [
      "currLog" ::= struct.loadF keyCli "log" "kc";
      "newLogB" ::= "newLogB";
      "uname" ::= struct.loadF shared.UnameKey "Uname" "entry";
      "doLookup" ::= #true
    ] in
    let: "out" := checkLog "in" in
    (if: (struct.loadF checkLogOut "err" "out") ≠ shared.ErrNone
    then (#0, struct.loadF checkLogOut "err" "out")
    else
      (if: (struct.loadF checkLogOut "epoch" "out") < (shared.KeyLog__Len (struct.loadF checkLogIn "currLog" "in"))
      then (#0, shared.ErrKeyCli_RegNoExist)
      else
        struct.storeF keyCli "log" "kc" (struct.loadF checkLogOut "newLog" "out");;
        (struct.loadF checkLogOut "epoch" "out", shared.ErrNone))).

Definition keyCli__lookup: val :=
  rec: "keyCli__lookup" "kc" "uname" :=
    let: "newLogB" := NewSlice byteT #0 in
    let: "err1" := urpc.Client__Call (struct.loadF keyCli "serv" "kc") shared.RpcGetLog slice.nil "newLogB" #100 in
    control.impl.Assume ("err1" = urpc.ErrNone);;
    let: "in" := struct.new checkLogIn [
      "currLog" ::= struct.loadF keyCli "log" "kc";
      "newLogB" ::= "newLogB";
      "uname" ::= "uname";
      "doLookup" ::= #true
    ] in
    let: "out" := checkLog "in" in
    (if: (struct.loadF checkLogOut "err" "out") ≠ shared.ErrNone
    then (#0, slice.nil, struct.loadF checkLogOut "err" "out")
    else
      struct.storeF keyCli "log" "kc" (struct.loadF checkLogOut "newLog" "out");;
      (struct.loadF checkLogOut "epoch" "out", struct.loadF checkLogOut "key" "out", shared.ErrNone)).

Definition keyCli__audit: val :=
  rec: "keyCli__audit" "kc" "aId" :=
    let: "sigLogB" := NewSlice byteT #0 in
    let: "err1" := urpc.Client__Call (SliceGet ptrT (struct.loadF keyCli "adtrs" "kc") "aId") shared.RpcGetAudit slice.nil "sigLogB" #100 in
    control.impl.Assume ("err1" = urpc.ErrNone);;
    let: "sigLog" := struct.alloc shared.SigLog (zero_val (struct.t shared.SigLog)) in
    let: (<>, "err2") := shared.SigLog__Decode "sigLog" "sigLogB" in
    (if: "err2" ≠ shared.ErrNone
    then (#0, "err2")
    else
      let: "logB" := shared.KeyLog__Encode (struct.loadF shared.SigLog "Log" "sigLog") in
      let: "err3" := kt_shim.VerifierT__Verify (SliceGet ptrT (struct.loadF keyCli "adtrKeys" "kc") "aId") (struct.loadF shared.SigLog "Sig" "sigLog") "logB" in
      (if: "err3" ≠ shared.ErrNone
      then (#0, "err3")
      else
        (if: (~ (shared.KeyLog__IsPrefix (struct.loadF keyCli "log" "kc") (struct.loadF shared.SigLog "Log" "sigLog")))
        then (#0, shared.ErrKeyCli_AuditPrefix)
        else
          struct.storeF keyCli "log" "kc" (struct.loadF shared.SigLog "Log" "sigLog");;
          (shared.KeyLog__Len (struct.loadF keyCli "log" "kc"), shared.ErrNone)))).

(* Two clients lookup the same uname, talk to the same honest auditor,
   and assert that their returned keys are the same. *)
Definition testAuditPass: val :=
  rec: "testAuditPass" "servAddr" "audAddr" :=
    Fork (let: "s" := newKeyServ #() in
          keyServ__start "s" "servAddr");;
    time.Sleep #1000000;;
    let: ("audSigner", "audVerifier") := kt_shim.MakeKeys #() in
    Fork (let: "a" := newAuditor "servAddr" "audSigner" in
          auditor__start "a" "audAddr");;
    time.Sleep #1000000;;
    let: "adtrs" := SliceSingleton "audAddr" in
    let: "adtrKeys" := SliceSingleton "audVerifier" in
    let: "cReg" := newKeyCli "servAddr" "adtrs" "adtrKeys" in
    let: "cLook1" := newKeyCli "servAddr" "adtrs" "adtrKeys" in
    let: "cLook2" := newKeyCli "servAddr" "adtrs" "adtrKeys" in
    let: "aliceUname" := #42 in
    let: "aliceKey" := StringToBytes #(str"pubkey") in
    let: "uk" := struct.new shared.UnameKey [
      "Uname" ::= "aliceUname";
      "Key" ::= "aliceKey"
    ] in
    let: (<>, "err1") := keyCli__register "cReg" "uk" in
    control.impl.Assume ("err1" = shared.ErrNone);;
    let: "audC" := urpc.MakeClient "audAddr" in
    let: "emptyB" := NewSlice byteT #0 in
    let: "err2" := urpc.Client__Call "audC" shared.RpcDoAudit slice.nil "emptyB" #100 in
    control.impl.Assume ("err2" = urpc.ErrNone);;
    let: (("epochL1", "retKey1"), "err") := keyCli__lookup "cLook1" "aliceUname" in
    control.impl.Assume ("err" = shared.ErrNone);;
    let: (("epochL2", "retKey2"), "err") := keyCli__lookup "cLook2" "aliceUname" in
    control.impl.Assume ("err" = shared.ErrNone);;
    let: (<>, "err3") := keyCli__audit "cLook1" #0 in
    control.impl.Assume ("err3" = shared.ErrNone);;
    let: (<>, "err4") := keyCli__audit "cLook2" #0 in
    control.impl.Assume ("err4" = shared.ErrNone);;
    (if: "epochL1" = "epochL2"
    then
      control.impl.Assert (shared.BytesEqual "retKey1" "retKey2");;
      #()
    else #()).

(* An auditor sees writes from a server. A user's lookup goes to
   a different server, but the user later contacts the auditor.
   The user's audit should return an error. *)
Definition testAuditFail: val :=
  rec: "testAuditFail" "servAddr1" "servAddr2" "audAddr" :=
    Fork (let: "s" := newKeyServ #() in
          keyServ__start "s" "servAddr1");;
    Fork (let: "s" := newKeyServ #() in
          keyServ__start "s" "servAddr2");;
    time.Sleep #1000000;;
    let: ("audSigner", "audVerifier") := kt_shim.MakeKeys #() in
    Fork (let: "a" := newAuditor "servAddr1" "audSigner" in
          auditor__start "a" "audAddr");;
    time.Sleep #1000000;;
    let: "adtrs" := SliceSingleton "audAddr" in
    let: "adtrKeys" := SliceSingleton "audVerifier" in
    let: "cReg1" := newKeyCli "servAddr1" "adtrs" "adtrKeys" in
    let: "cReg2" := newKeyCli "servAddr2" "adtrs" "adtrKeys" in
    let: "cLook2" := newKeyCli "servAddr2" "adtrs" "adtrKeys" in
    let: "aliceUname" := #42 in
    let: "aliceKey1" := StringToBytes #(str"pubkey1") in
    let: "aliceKey2" := StringToBytes #(str"pubkey2") in
    let: "uk1" := struct.new shared.UnameKey [
      "Uname" ::= "aliceUname";
      "Key" ::= "aliceKey1"
    ] in
    let: "uk2" := struct.new shared.UnameKey [
      "Uname" ::= "aliceUname";
      "Key" ::= "aliceKey2"
    ] in
    let: (<>, "err1") := keyCli__register "cReg1" "uk1" in
    control.impl.Assume ("err1" = shared.ErrNone);;
    let: (<>, "err2") := keyCli__register "cReg2" "uk2" in
    control.impl.Assume ("err2" = shared.ErrNone);;
    let: "audC" := urpc.MakeClient "audAddr" in
    let: "emptyB" := NewSlice byteT #0 in
    let: "err3" := urpc.Client__Call "audC" shared.RpcDoAudit slice.nil "emptyB" #100 in
    control.impl.Assume ("err3" = urpc.ErrNone);;
    let: ((<>, <>), "err4") := keyCli__lookup "cLook2" "aliceUname" in
    control.impl.Assume ("err4" = shared.ErrNone);;
    let: (<>, "err5") := keyCli__audit "cLook2" #0 in
    control.impl.Assert ("err5" = shared.ErrKeyCli_AuditPrefix);;
    #().
