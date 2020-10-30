From Coq.Structures Require Import OrdersTac.
From stdpp Require Import gmap.
From iris.algebra Require Import numbers.
From iris.program_logic Require Export weakestpre.
From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Import ffi.disk_prelude.
From Perennial.goose_lang Require Import notation.
From Perennial.program_proof Require Import proof_prelude.
From RecordUpdate Require Import RecordUpdate.
From Perennial.algebra Require Import auth_map fmcounter.
From Perennial.goose_lang.lib Require Import lock.
From Perennial.Helpers Require Import NamedProps Integers.
From Perennial.Helpers Require Import ModArith.
From Perennial.program_proof.lockservice Require Import lockservice fmcounter_map rpc common_proof nondet rpc proof kv_proof.

Record bank_names := BankGN {
  bank_ls_names : lockservice_names;
  bank_ks_names : kvservice_names;
  bank_logBalGN : gname (* *)
}.

Class bankG Σ := BankG {
  bank_ls :> lockserviceG Σ;
  bank_ks :> kvserviceG Σ;
  (* bank_logBalG :> mapG Σ u64 u64 *)
}.

Section bank_proof.
Context `{!heapG Σ, !bankG Σ}.

Implicit Types (γ : bank_names).

Context `{acc1:u64, acc2:u64, bal_total:Z}. (* Account names and total balance for bank; using Z for 
                                               anything involking arithmetic *)

Definition kv_gn γ := γ.(bank_ks_names).(ks_kvMapGN).
Definition log_gn γ := γ.(bank_logBalGN).

Definition bankPs γ := λ k, (∃v, k [[kv_gn γ]]↦v ∗ k [[log_gn γ]]↦v)%I.

(* TODO: consider making is_*server part of own_*clerk *)
Definition own_bank_clerk (bank_ck:loc) γ : iProp Σ :=
  ∃ (lck kck ls_srv ks_srv:loc), 
  "%" ∷ ⌜acc1 ≠ acc2⌝ ∗
  "#Hls" ∷ is_lockserver ls_srv γ.(bank_ls_names) (Ps:=bankPs γ) ∗
  "#Hks" ∷ is_kvserver ks_srv γ.(bank_ks_names) ∗
  "Hlck_own" ∷ own_clerk #lck ls_srv γ.(bank_ls_names).(ls_rpcGN) ∗
  "Hkck_own" ∷ own_kvclerk kck ks_srv γ.(bank_ks_names).(ks_rpcGN) ∗

  "Hkck" ∷ bank_ck ↦[BankClerk.S :: "kvck"] #kck ∗
  "Hlck" ∷ bank_ck ↦[BankClerk.S :: "lck"] #lck ∗
  "Hacc1" ∷ bank_ck ↦[BankClerk.S :: "acc1"] #acc1 ∗
  "Hacc1" ∷ bank_ck ↦[BankClerk.S :: "acc2"] #acc2 ∗

  "Hacc1_is_lock" ∷ lockservice_is_lock γ.(bank_ls_names) acc1 ∗
  "Hacc2_is_lock" ∷ lockservice_is_lock γ.(bank_ls_names) acc2
.

Definition bank_inv γ : iProp Σ :=
  ∃ (bal1 bal2:u64),
  "HlogBalCtx" ∷ map_ctx (log_gn γ) 1 ({[ acc1:=bal1 ]} ∪ {[ acc2:=bal2 ]}) ∗
  "%" ∷ ⌜(int.Z bal1 + int.Z bal2 = bal_total)%Z⌝
  .

Definition bankN := nroot .@ "bank".

Lemma acquire_two_spec (lck lsrv :loc) (ln1 ln2:u64) γ:
let γrpc := γ.(bank_ls_names).(ls_rpcGN) in
{{{
     is_lockserver lsrv γ.(bank_ls_names) (Ps:=bankPs γ) ∗
     own_clerk #lck lsrv γrpc
}}}
  acquire_two #lck #ln1 #ln2
{{{
     RET #(); own_clerk #lck lsrv γrpc ∗
     bankPs γ ln1 ∗
     bankPs γ ln2
}}}.
Proof.
Admitted.

Lemma release_two_spec (lck lsrv :loc) (ln1 ln2:u64) γ:
let γrpc := γ.(bank_ls_names).(ls_rpcGN) in
{{{
     is_lockserver lsrv γ.(bank_ls_names) (Ps:=bankPs γ) ∗
     bankPs γ ln1 ∗
     bankPs γ ln2 ∗
     own_clerk #lck lsrv γrpc
}}}
  release_two #lck #ln1 #ln2
{{{
     RET #(); own_clerk #lck lsrv γrpc
}}}.
Proof.
Admitted.

Lemma Bank__SimpleTransfer_spec (bck:loc) (amount:u64) γ :
{{{
     inv bankN (bank_inv γ) ∗
     own_bank_clerk bck γ
}}}
  BankClerk__SimpleTransfer #bck #amount
{{{
     RET #();
     own_bank_clerk bck γ
}}}.
Proof.
  iIntros (Φ) "[#Hbinv Hpre] Hpost".
  iNamed "Hpre".
  (* FIXME: iNamed not working correctly? *)
  iDestruct "Hpre" as "(Hacc1 & Hacc2 & #Hacc_is_lock)".
  iNamed "Hacc_is_lock".
  wp_lam. wp_pures.
  wp_loadField.
  wp_loadField.
  wp_lam. (* We just use the helper function in-line *)
  wp_pures.
  wp_loadField.
  wp_apply (acquire_two_spec with "[$Hlck_own $Hls]").
  iIntros "(Hlck_own & Hacc1_unlocked & Hacc2_unlocked)".
  iDestruct "Hacc1_unlocked" as (bal1) "(Hacc1_phys & Hacc1_log)".
  iDestruct "Hacc2_unlocked" as (bal2) "(Hacc2_phys & Hacc2_log)".
  wp_pures.
  wp_loadField.
  wp_apply (KVClerk__Get_spec with "[$Hkck_own $Hks Hacc1_phys]"); first eauto.
  iIntros (v_bal1_g) "Hbal1_get".
  iDestruct "Hbal1_get" as (->) "[Hkck_own Hacc1_phys]".
  wp_pures.
  destruct bool_decide eqn:HenoughBalance; wp_pures.
  - wp_loadField. wp_apply (KVClerk__Put_spec with "[$Hkck_own $Hks Hacc1_phys]"); first eauto.
    iIntros "[Hkck_own Hacc1_phys]".
    wp_pures.
    wp_loadField.
    wp_apply (KVClerk__Get_spec with "[$Hkck_own $Hks Hacc2_phys]"); first eauto.
    iIntros (v_bal2_g) "Hbal2_get".
    iDestruct "Hbal2_get" as (->) "[Hkck_own Hacc2_phys]".
    wp_loadField.
    wp_apply (KVClerk__Put_spec with "[$Hkck_own $Hks Hacc2_phys]"); first eauto.
    iIntros "[Hkck_own Hacc2_phys]".
    wp_pures.
    iApply fupd_wp.
    iInv bankN as ">HbankInv" "HbankInvClose".
    iNamed "HbankInv".
    iMod (map_update acc1 _ (word.sub bal1 amount) with "HlogBalCtx Hacc1_log") as "[HlogBalCtx Hacc1_log]".
    iMod (map_update acc2 _ (word.add bal2 amount) with "HlogBalCtx Hacc2_log") as "[HlogBalCtx Hacc2_log]".
    iMod ("HbankInvClose" with "[HlogBalCtx]") as "_".
    { iNext. iExists _, _. iSplitL "HlogBalCtx".
      - rewrite insert_union_l. rewrite insert_singleton. 
        rewrite insert_union_r; last by apply lookup_singleton_ne. rewrite insert_singleton. 
        iFrame.
      - admit. (* FIXME: add the necessary overflow checks and use them here... *)
    }
    iModIntro.
    wp_loadField.
    wp_apply (release_two_spec with "[$Hlck_own $Hls Hacc1_phys Hacc2_phys Hacc1_log Hacc2_log]").
    { iSplitL "Hacc1_phys Hacc1_log"; iExists _; iFrame. }
    iIntros "Hlck_own".
    iApply "Hpost".
    iExists _, _, _, _; iFrame "∗ # %".
  - wp_loadField. wp_apply (release_two_spec with "[$Hlck_own $Hls Hacc1_phys Hacc2_phys Hacc1_log Hacc2_log]").
    { iSplitL "Hacc1_phys Hacc1_log"; iExists _; iFrame. }
    iIntros "Hlck_own".
    iApply "Hpost".
    iExists _, _, _, _; iFrame "∗ # %".
Admitted.

End bank_proof.