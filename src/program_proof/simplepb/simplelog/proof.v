From Perennial.program_proof Require Import grove_prelude.
From Perennial.program_proof Require Import marshal_stateless_proof.
From coqutil.Datatypes Require Import List.
From Perennial.goose_lang Require Import crash_borrow.
From Perennial.program_proof.fencing Require Import map.
From Perennial.algebra Require Import mlist.

From Perennial.program_proof.aof Require Import proof.
From Perennial.program_proof.simplepb Require Import pb_start_proof pb_definitions.
From Goose.github_com.mit_pdos.gokv.simplepb Require Export simplelog.

Section proof.

Context {sm_record:PBRecord}.
Notation OpType := (pb_OpType sm_record).
Notation has_op_encoding := (pb_has_op_encoding sm_record).
Notation has_snap_encoding := (pb_has_snap_encoding sm_record).
Notation compute_reply := (pb_compute_reply sm_record).
Instance e : EqDecision OpType := (pb_OpType_EqDecision sm_record).
Notation pbG := (pbG (pb_record:=sm_record)).
Notation pbΣ := (pbΣ (pb_record:=sm_record)).

Class simplelogG Σ := SimplelogG {
  simplelog_fmlistG :> fmlistG (u64 * (list OpType) * bool) Σ;
  simplelog_aofG :> aofG Σ ;
  simplelog_pbG :> pbG Σ ;
}.

Definition simplelogΣ := #[
  fmlistΣ (u64 * list (OpType) * bool) ;
  aofΣ ;
  pbΣ
].

Global Instance subG_simplelogΣ {Σ} : subG simplelogΣ Σ → simplelogG Σ.
Proof. solve_inG. Qed.

Context `{!heapGS Σ}.
Context `{!simplelogG Σ}.

(* Want to prove *)

Definition file_encodes_state (data:list u8) (epoch:u64) (ops: list OpType) (sealed:bool): Prop :=
  ∃ snap_ops snap (rest_ops:list OpType) (rest_ops_bytes:list (list u8)) sealed_bytes,
    ops = snap_ops ++ rest_ops ∧
    has_snap_encoding snap snap_ops ∧
    sealed_bytes = match sealed with false => [] | true => [U8 0] end /\
    length rest_ops = length rest_ops_bytes ∧
    (∀ (i:nat), i < length rest_ops →
          ∃ op op_len_bytes op_bytes,
            rest_ops !! i = Some op ∧
              rest_ops_bytes !! i = Some (op_len_bytes ++ op_bytes) ∧
              has_op_encoding op_bytes op /\
              op_len_bytes = u64_le (length op_bytes)
    ) ∧

    (length ops < 2^64)%Z ∧
    data = (u64_le (length snap)) ++ snap ++ (u64_le epoch) ++ (u64_le (length snap_ops)) ++
                         (concat rest_ops_bytes) ++ sealed_bytes
.

Lemma file_encodes_state_nonempty data epoch ops sealed :
  file_encodes_state data epoch ops sealed → length data > 0.
Proof.
  destruct 1 as (snap_ops&snap&rest_ops&rest_ops_bytes&sealed_bytes&Heq&Henc&Hsealed&Hlen&Henc'&?&Hdata).
  rewrite Hdata. rewrite ?app_length.
  rewrite u64_le_length; lia.
Qed.

Lemma file_encodes_state_append op op_bytes data epoch ops :
  (length ops + 1 < 2 ^ 64)%Z →
  has_op_encoding op_bytes op →
  file_encodes_state data epoch ops false →
  file_encodes_state (data ++ (u64_le (length op_bytes)) ++ op_bytes) epoch (ops++[op]) false
.
Proof.
  rewrite /file_encodes_state.
  intros Hoverflow Hop_enc Hf_enc.
  destruct Hf_enc as (snap_ops&snap&rest_ops&rest_ops_bytes&sealed_bytes&Heq_ops&Hsnaop_enc&Hsealed&Hlen&Hrest&?&Heq_data).
  do 3 eexists.
  exists (rest_ops_bytes ++ [u64_le (length op_bytes) ++ op_bytes]).
  exists [].
  split_and!.
  { rewrite Heq_ops. rewrite -app_assoc. f_equal. }
  { eauto. }
  { auto. }
  { rewrite ?app_length /=; lia. }
  { intros i Hlt.
    rewrite ?app_length /= in Hlt.
    destruct (decide (i = length rest_ops)); last first.
    { edestruct (Hrest i) as (op'&op_len_bytes'&op_bytes'&Hlookup1&Hlookup2&Henc'&Hlenenc'); eauto.
      { lia. }
      do 3 eexists; split_and!; eauto.
      { rewrite lookup_app_l; auto; lia. }
      { rewrite lookup_app_l; auto; lia. }
    }
    {
      subst. exists op, (u64_le (length op_bytes)), op_bytes. split_and!; eauto.
      { rewrite lookup_app_r ?list_lookup_singleton; auto. rewrite Nat.sub_diag //. }
      { rewrite lookup_app_r ?list_lookup_singleton; auto; try lia.
        rewrite Hlen. rewrite Nat.sub_diag //. }
    }
  }
  { rewrite ?app_length /=. lia. }
  { rewrite Heq_data. rewrite -?app_assoc.
    rewrite Hsealed.
    rewrite ?concat_app -?app_assoc. do 4 f_equal.
    rewrite /concat app_nil_r // app_nil_r //.
  }
Qed.

Lemma file_encodes_state_snapshot snap ops epoch :
  (length ops < 2 ^ 64)%Z →
  has_snap_encoding snap ops →
  file_encodes_state ((u64_le (length snap) ++ snap) ++ u64_le epoch ++ u64_le (length ops))
    epoch ops false
.
Proof.
  rewrite /file_encodes_state.
  intros Henc.
  exists ops, snap, [], [], [].
  rewrite ?app_nil_r. split_and!; auto.
  { simpl. intros. lia. }
Qed.

Lemma file_encodes_state_seal data ops epoch :
  file_encodes_state data epoch ops false →
  file_encodes_state (data ++ [U8 0]) epoch ops true
.
Proof.
  destruct 1 as
    (snap_ops&snap&rest_ops&rest_ops_bytes&sealed_bytes&Heq_ops&Hsnaop_enc&Hsealed&Hlen&Hrest&?&Heq_data).
  exists snap_ops, snap, rest_ops, rest_ops_bytes, [U8 0].
  split_and!; eauto.
  rewrite Heq_data Hsealed. rewrite -?app_assoc app_nil_l //.
Qed.

Implicit Types (P:u64 → list OpType → bool → iProp Σ).

Implicit Types own_InMemoryStateMachine : list OpType → iProp Σ.

Definition is_InMemory_applyVolatileFn (applyVolatileFn:val) own_InMemoryStateMachine : iProp Σ :=
  ∀ ops op op_sl op_bytes,
  {{{
        ⌜has_op_encoding op_bytes op⌝ ∗
        readonly (is_slice_small op_sl byteT 1 op_bytes) ∗
        own_InMemoryStateMachine ops
  }}}
    applyVolatileFn (slice_val op_sl)
  {{{
        reply_sl q, RET (slice_val reply_sl);
        own_InMemoryStateMachine (ops ++ [op]) ∗
        is_slice_small reply_sl byteT q (compute_reply ops op)
  }}}
.

Definition is_InMemory_setStateFn (setStateFn:val) own_InMemoryStateMachine : iProp Σ :=
  ∀ ops_prev ops snap snap_sl,
  {{{
        ⌜has_snap_encoding snap ops⌝ ∗
        readonly (is_slice_small snap_sl byteT 1 snap) ∗
        own_InMemoryStateMachine ops_prev
  }}}
    setStateFn (slice_val snap_sl)
  {{{
        RET #(); own_InMemoryStateMachine ops
  }}}
.

Definition is_InMemory_getStateFn (getStateFn:val) own_InMemoryStateMachine : iProp Σ :=
  ∀ ops,
  {{{
        own_InMemoryStateMachine ops
  }}}
    getStateFn #()
  {{{
        snap snap_sl, RET (slice_val snap_sl); own_InMemoryStateMachine ops ∗
        ⌜has_snap_encoding snap ops⌝ ∗
        readonly (is_slice_small snap_sl byteT 1 snap)
  }}}
.

Record simplelog_names :=
{
  (* file_encodes_state is not injective, so we use this state to
     remember that "for the 5th append, the (epoch, ops, sealed) was X".
     For each possible length, there's a potential read-only proposal.
   *)
  sl_state : gname;
}.

Definition file_inv γ P (contents:list u8) : iProp Σ :=
  ∃ epoch ops sealed,
  ⌜file_encodes_state contents epoch ops sealed⌝ ∗
  P epoch ops sealed ∗
  fmlist_idx γ.(sl_state) (length contents) (epoch, ops, sealed)
.

Definition file_crash P (contents:list u8) : iProp Σ :=
  ⌜contents = []⌝ ∗ P 0 [] false
  ∨
  ∃ epoch ops sealed,
    ⌜file_encodes_state contents epoch ops sealed⌝ ∗
    P epoch ops sealed
.

Definition is_InMemoryStateMachine (sm:loc) own_InMemoryStateMachine : iProp Σ :=
  ∃ applyVolatileFn setStateFn getStateFn,
  "#HapplyVolatile" ∷ readonly (sm ↦[InMemoryStateMachine :: "ApplyVolatile"] applyVolatileFn) ∗
  "#HapplyVolatile_spec" ∷ is_InMemory_applyVolatileFn applyVolatileFn own_InMemoryStateMachine ∗

  "#HsetState" ∷ readonly (sm ↦[InMemoryStateMachine :: "SetState"] setStateFn) ∗
  "#HsetState_spec" ∷ is_InMemory_setStateFn setStateFn own_InMemoryStateMachine ∗

  "#HgetState" ∷ readonly (sm ↦[InMemoryStateMachine :: "GetState"] getStateFn) ∗
  "#HgetState_spec" ∷ is_InMemory_getStateFn getStateFn own_InMemoryStateMachine
.

Definition own_StateMachine (s:loc) (epoch:u64) (ops:list OpType) (sealed:bool) P : iProp Σ :=
  ∃ (fname:string) (aof_ptr:loc) γ γaof (logsize:u64) (smMem_ptr:loc) data
    own_InMemoryStateMachine allstates,
    "Hfname" ∷ s ↦[StateMachine :: "fname"] #(LitString fname) ∗
    "HlogFile" ∷ s ↦[StateMachine :: "logFile"] #aof_ptr ∗
    "HsmMem" ∷ s ↦[StateMachine :: "smMem"] #smMem_ptr ∗
    "HnextIndex" ∷ s ↦[StateMachine :: "nextIndex"] #(U64 (length ops)) ∗
    "Hlogsize" ∷ s ↦[StateMachine :: "logsize"] #logsize ∗
    "Hepoch" ∷ s ↦[StateMachine :: "epoch"] #epoch ∗
    "Hsealed" ∷ s ↦[StateMachine :: "sealed"] #sealed ∗
    "#Hdurlb" ∷ □(if sealed then aof_durable_lb γaof data else True) ∗

    "Haof" ∷ aof_log_own γaof data ∗
    "#His_aof" ∷ is_aof aof_ptr γaof fname (file_inv γ P) (file_crash P) ∗
    "%Henc" ∷ ⌜file_encodes_state data epoch ops sealed⌝ ∗
    "Hmemstate" ∷ own_InMemoryStateMachine ops ∗
    "#HisMemSm" ∷ is_InMemoryStateMachine smMem_ptr own_InMemoryStateMachine ∗

    "%Hopssafe" ∷ ⌜length ops = int.nat (length ops)⌝ ∗

    "#Hcur_state_var" ∷ fmlist_idx γ.(sl_state) (length data) (epoch, ops, sealed) ∗
    "Hallstates" ∷ fmlist γ.(sl_state) (DfracOwn 1) allstates ∗
    "%Hallstates_len" ∷ ⌜length allstates = (length data + 1)%nat⌝
.

Lemma wp_StateMachine__apply s Q (op:OpType) (op_bytes:list u8) op_sl epoch ops P :
  {{{
        ⌜has_op_encoding op_bytes op⌝ ∗
        readonly (is_slice_small op_sl byteT 1 op_bytes) ∗
        (P epoch ops false ={⊤∖↑aofN}=∗ P epoch (ops ++ [op]) false ∗ Q) ∗
        own_StateMachine s epoch ops false P
  }}}
    StateMachine__apply #s (slice_val op_sl)
  {{{
        reply_sl q (waitFn:goose_lang.val),
        RET (slice_val reply_sl, waitFn);
        is_slice_small reply_sl byteT q (compute_reply ops op) ∗
        own_StateMachine s epoch (ops ++ [op]) false P ∗
        (∀ Ψ, (Q -∗ Ψ #()) -∗ WP waitFn #() {{ Ψ }})
  }}}
.
Proof.
  iIntros (Φ) "(%HopEnc & #Hop_sl & Hupd & Hown) HΦ".
  wp_lam.
  wp_pures.

  iNamed "Hown".

  (* first, apply the operation in memory and to compute the reply *)
  iAssert (_) with "HisMemSm" as "#HisMemSm2".
  iNamed "HisMemSm2".
  wp_loadField.
  wp_loadField.
  wp_apply ("HapplyVolatile_spec" with "[$Hmemstate]").
  {
    iFrame "#".
    done.
  }
  iIntros (??) "[Hmemstate Hreply_sl]".
  wp_pures.

  wp_loadField.
  wp_apply (std_proof.wp_SumAssumeNoOverflow).
  iIntros (HnextIndexOverflow).

  wp_storeField.
  wp_loadField.
  wp_apply (wp_slice_len).
  wp_storeField.

  (* make opWithLen *)
  iMod (readonly_load with "Hop_sl") as (?) "Hop_sl2".
  iDestruct (is_slice_small_sz with "Hop_sl2") as %Hop_sz.
  wp_apply (wp_slice_len).
  wp_apply (wp_NewSliceWithCap).
  { apply encoding.unsigned_64_nonneg. }
  iIntros (?) "HopWithLen_sl".
  wp_apply (wp_ref_to).
  { done. }
  iIntros (opWithLen_sl_ptr) "HopWithLen".
  wp_pures.
  wp_apply wp_slice_len.
  wp_load.
  wp_apply (wp_WriteInt with "[$HopWithLen_sl]").
  iIntros (opWithLen_sl) "HopWithLen_sl".
  wp_store.
  wp_load.
  wp_apply (wp_WriteBytes with "[$HopWithLen_sl $Hop_sl2]").
  rename opWithLen_sl into opWithLen_sl_old.
  iIntros (opWithLen_sl) "[HopWithLen_sl _]".
  wp_store.

  (* start append on logfile *)
  wp_load.
  wp_loadField.

  iDestruct (is_slice_to_small with "HopWithLen_sl") as "HopWithLen_sl".

  (* simplify marshalled opWithLen list *)
  replace (int.nat 0) with (0%nat) by word.
  rewrite replicate_0.
  rewrite app_nil_l.
  replace (op_sl.(Slice.sz)) with (U64 (length op_bytes)); last first.
  { word. }

  set (newsuffix:=u64_le (length op_bytes) ++ op_bytes).
  set (newdata:=data ++ newsuffix).

  (* make proposal *)
  iMod (fmlist_update with "Hallstates") as "[Hallstates Hallstates_lb]".
  {
    instantiate (1:=allstates ++ (replicate (length newsuffix) (epoch, ops ++ [op], false))).
    apply prefix_app_r.
    done.
  }

  iDestruct (fmlist_lb_to_idx _ _ (length newdata) with "Hallstates_lb") as "#Hcurstate".
  {
    unfold newdata.
    rewrite app_length.
    assert (1 <= length newsuffix).
    {
      unfold newsuffix.
      rewrite app_length.
      rewrite u64_le_length.
      word.
    }
    rewrite lookup_app_r; last first.
    { word. }
    rewrite Hallstates_len.
    replace (length data + length newsuffix - (length data + 1))%nat with
      (length newsuffix - 1)%nat by word.
    apply lookup_replicate.
    split; last lia.
    done.
  }

  iDestruct (is_slice_small_sz with "HopWithLen_sl") as %HopWithLen_sz.
  wp_apply (wp_AppendOnlyFile__Append with "His_aof [$Haof $HopWithLen_sl Hupd]").
  { rewrite app_length. rewrite u64_le_length. word. }
  {
    unfold list_safe_size.
    word.
  }
  {
    instantiate (1:=Q).
    iIntros "Hi".
    iDestruct "Hi" as (???) "(%Henc2 & HP & #Hghost2)".
    iDestruct (fmlist_idx_agree_1 with "Hcur_state_var Hghost2") as "%Heq".
    replace (epoch0) with (epoch) by naive_solver.
    replace (ops0) with (ops) by naive_solver.
    replace (sealed) with (false) by naive_solver.

    iMod ("Hupd" with "HP") as "[HP $]".
    iModIntro.
    iExists _, (ops ++ [op]), _.
    iFrame "HP".
    rewrite app_length.
    rewrite app_length.
    rewrite u64_le_length.
    iFrame "#".
    iPureIntro.
    apply file_encodes_state_append; auto.
    word.
  }
  iIntros (l) "[Haof HupdQ]".
  wp_pures.
  wp_loadField.
  wp_pures.
  iModIntro.
  iApply "HΦ".
  iFrame.
  iSplitR "HupdQ".
  {
    iExists fname, _, γ, _, _, _, _, _.
    iExists _.
    iFrame "∗#".
    repeat rewrite app_length. rewrite u64_le_length.
    iFrame "∗#".
    iSplitL; last first.
    { iPureIntro.
      split.
      { apply file_encodes_state_append; auto. word. }
      { rewrite Hallstates_len.
        rewrite replicate_length.
        simpl.
        word. }
    }
    iApply to_named.
    iExactEq "HnextIndex".
    repeat f_equal.
    simpl.
    word.
  }
  iIntros (Ψ) "HΨ".
  wp_call.
  wp_apply (wp_AppendOnlyFile__WaitAppend with "[$His_aof]").
  iIntros "Haof_len".
  iMod ("HupdQ" with "Haof_len") as "[HQ _]".
  wp_pures.
  iModIntro.
  iApply "HΨ".
  iFrame.
Qed.

Lemma wp_setStateAndUnseal s P ops_prev (epoch_prev:u64) sealed_prev ops epoch (snap:list u8) snap_sl Q :
  {{{
        ⌜ (length ops < 2 ^ 64)%Z ⌝ ∗
        ⌜has_snap_encoding snap ops⌝ ∗
        readonly (is_slice_small snap_sl byteT 1 snap) ∗
        (P epoch_prev ops_prev sealed_prev ={⊤}=∗ P epoch ops false ∗ Q) ∗
        own_StateMachine s epoch_prev ops_prev sealed_prev P
  }}}
    StateMachine__setStateAndUnseal #s (slice_val snap_sl) #(U64 (length ops)) #epoch
  {{{
        RET #();
        own_StateMachine s epoch ops false P ∗ Q
  }}}
.
Proof.
  iIntros (Φ) "(%HsnapLen & %HsnapEnc & #Hsnap_sl & Hupd & Hown) HΦ".
  wp_lam.
  wp_pures.
  iNamed "Hown".

  wp_storeField.
  wp_storeField.
  wp_storeField.

  iAssert (_) with "HisMemSm" as "#HisMemSm2".
  iNamed "HisMemSm2".
  wp_loadField.
  wp_loadField.
  wp_apply ("HsetState_spec" with "[$Hsnap_sl $Hmemstate]").
  { done. }
  iIntros "Hmemstate".

  wp_pures.

  (* XXX: this could be a separate lemma *)
  wp_lam.
  wp_pures.

  (* create contents of brand new file *)

  wp_apply (wp_slice_len).
  wp_apply (wp_NewSliceWithCap).
  { apply encoding.unsigned_64_nonneg. }

  iIntros (?) "Henc_sl".
  wp_apply (wp_ref_to).
  { done. }
  iIntros (enc_ptr) "Henc".
  wp_pures.
  wp_apply (wp_slice_len).
  wp_load.
  wp_apply (wp_WriteInt with "[$Henc_sl]").
  iIntros (enc_sl) "Henc_sl".
  wp_pures.
  wp_store.

  wp_load.
  iMod (readonly_load with "Hsnap_sl") as (?) "Hsnap_sl2".
  iDestruct (is_slice_small_sz with "Hsnap_sl2") as "%Hsnap_sz".
  wp_apply (wp_WriteBytes with "[$Henc_sl $Hsnap_sl2]").
  iIntros (enc_sl2) "[Henc_sl _]".
  wp_store.

  wp_loadField.
  wp_load.
  wp_apply (wp_WriteInt with "[$Henc_sl]").
  iIntros (enc_sl3) "Henc_sl".
  wp_pures.
  wp_store.

  wp_loadField.
  wp_load.
  wp_apply (wp_WriteInt with "[$Henc_sl]").
  iIntros (enc_sl4) "Henc_sl".
  wp_pures.
  wp_store.

  replace (int.nat 0) with (0%nat) by word.
  rewrite replicate_0.
  rewrite app_nil_l.
  replace (snap_sl.(Slice.sz)) with (U64 (length snap)); last first.
  { word. }

  wp_loadField.
  wp_pures.

  wp_loadField.

  wp_apply (wp_AppendOnlyFile__Close with "His_aof [$Haof]").
  iIntros "Hfile".
  wp_pures.

  wp_load.
  wp_loadField.

  wp_bind (FileWrite _ _).
  iApply (wpc_wp _ _ _ _ True).

  wpc_apply (wpc_crash_borrow_open_modify with "Hfile").
  { done. }
  iSplit; first done.
  iIntros "[Hfile Hinv]".
  iDestruct (is_slice_to_small with "Henc_sl") as "Henc_sl".
  iApply wpc_fupd.
  iDestruct (is_slice_small_sz with "Henc_sl") as %Henc_sz.
  wpc_apply (wpc_FileWrite with "[$Hfile $Henc_sl]").
  iSplit.
  { (* case: crash; *)
    iIntros "[Hbefore|Hafter]".
    {
      iSplitR; first done.
      iModIntro; iExists _; iFrame.
      iDestruct "Hinv" as (???) "[H1 [H2 H3]]".
      iRight.
      iExists _,_,_; iFrame.
    }
    { (* fire update; this is the same as the reasoning in the non-crash case *)
      iSplitR; first done.

      iDestruct "Hinv" as (???) "(%Henc2 & HP & #Hghost2)".
      iDestruct (fmlist_idx_agree_1 with "Hcur_state_var Hghost2") as "%Heq".
      replace (epoch0) with (epoch_prev) by naive_solver.
      replace (ops0) with (ops_prev) by naive_solver.
      replace (sealed) with (sealed_prev) by naive_solver.

      (* Want to change the gname for the γ variable that tracks
         proposals we've made so far, since we're going to make a new aof. This
         means γ can't show up in the crash condition. So, we need aof to have a
         different P in the crash condition and in the current resources. *)
      iMod ("Hupd" with "HP") as "[HP _]".
      iModIntro. iExists _; iFrame.
      iRight.
      iExists _, _, _; iFrame "HP".
      iPureIntro.
      rewrite -app_assoc.
      by apply file_encodes_state_snapshot.
    }
  }
  iNext.
  iIntros "[Hfile _]".

  iClear "Hallstates".
  iMod (fmlist_alloc []) as (γcur_state2) "Hallstates".
  set (γ2:={| sl_state := γcur_state2 |} ).

  (* update file_inv *)

  iDestruct "Hinv" as (???) "(%Henc2 & HP & #Hghost2)".
  iDestruct (fmlist_idx_agree_1 with "Hcur_state_var Hghost2") as "%Heq".
  replace (epoch0) with (epoch_prev) by naive_solver.
  replace (ops0) with (ops_prev) by naive_solver.
  replace (sealed) with (sealed_prev) by naive_solver.

  iMod ("Hupd" with "HP") as "[HP HQ]".

  rewrite -app_assoc.
  set (newdata:=(u64_le (length snap) ++ snap) ++ u64_le epoch ++ u64_le (length ops)).
  (* set new allstates *)

  iMod (fmlist_update with "Hallstates") as "[Hallstates Hallstates_lb]".
  {
    instantiate (1:=(replicate (length newdata + 1) (epoch, ops, false))).
    apply prefix_nil.
  }

  iDestruct (fmlist_lb_to_idx _ _ (length newdata) with "Hallstates_lb") as "#Hcurstate".
  {
    unfold newdata.
    rewrite app_length.
    apply lookup_replicate.
    split; last lia.
    done.
  }

  iAssert (file_inv γ2 P newdata) with "[HP]" as "HP".
  {
    iExists _, _, _; iFrame "HP #".
    iPureIntro.
    unfold newdata.
    rewrite -app_assoc.
    by apply file_encodes_state_snapshot.
  }
  iModIntro.
  iExists _.
  iSplitL "Hfile HP".
  { iAccu. }
  iSplit.
  {
    iModIntro.
    iIntros "[Hfile HP]".
    iModIntro. iExists _; iFrame.
    iDestruct "HP" as (???) "[H1 [H2 H3]]".
    iRight.
    iExists _,_,_; iFrame.
  }
  iIntros "Hfile".
  iSplit; first done.
  wp_pures.
  wp_loadField.

  wp_apply (wp_CreateAppendOnlyFile _ _ (file_inv γ2 P) (file_crash P) with "[] [$Hfile]").
  {
    iModIntro. iIntros (?) "Hinv".
    iDestruct "Hinv" as (???) "[H1 [H2 H3]]".
    iRight.
    iExists _,_,_; iFrame.
    by iModIntro.
  }
  iClear "His_aof".
  iIntros (new_aof_ptr γaof2) "(His_aof & Haof & #HdurableLb)".
  wp_storeField.
  wp_pures.
  iApply "HΦ".
  iFrame "HQ".
  iModIntro.
  iExists fname, new_aof_ptr, γ2, γaof2, _, _, newdata, own_InMemoryStateMachine.
  iExists _.
  iFrame "∗".
  iFrame "#".
  iSplitR; first done.
  iSplitR.
  {
    iPureIntro.
    unfold newdata.
    rewrite -app_assoc.
    by apply file_encodes_state_snapshot.
  }
  iPureIntro.
  unfold newdata.
  rewrite replicate_length.
  split.
  { word. }
  word.
Qed.

Lemma wp_getStateAndSeal s P epoch ops sealed Q :
  {{{
        own_StateMachine s epoch ops sealed P ∗
        (P epoch ops sealed ={⊤∖↑aofN}=∗ P epoch ops true ∗ Q)
  }}}
    StateMachine__getStateAndSeal #s
  {{{
        snap_sl snap,
        RET (slice_val snap_sl);
        readonly (is_slice_small snap_sl byteT 1 snap) ∗
        ⌜has_snap_encoding snap ops⌝ ∗
        own_StateMachine s epoch ops true P ∗
        Q
  }}}.
Proof.
  iIntros (Φ) "(Hown & Hupd) HΦ".
  wp_lam.
  wp_pures.

  iNamed "Hown".
  wp_loadField.

  wp_pures.
  wp_if_destruct.
  { (* case: not sealed previously *)
    wp_storeField.
    wp_apply (wp_NewSlice).
    iIntros (seal_sl) "Hseal_sl".
    wp_loadField.
    iDestruct (is_slice_to_small with "Hseal_sl") as "Hseal_sl".

    iMod (fmlist_update with "Hallstates") as "[Hallstates Hallstates_lb]".
    {
      instantiate (1:=(allstates ++ [(epoch, ops, true)])).
      apply prefix_app_r.
      done.
    }

    iDestruct (fmlist_lb_to_idx _ _ (length (data ++ [U8 0])) with "Hallstates_lb") as "#Hcurstate".
    {
      rewrite app_length.
      simpl.
      rewrite lookup_app_r; last first.
      { word. }
      rewrite Hallstates_len.
      rewrite Nat.sub_diag.
      done.
    }

    wp_apply (wp_AppendOnlyFile__Append with "His_aof [$Haof $Hseal_sl Hupd]").
    { by compute. }
    { by compute. }
    {
      iIntros "Hinv".
      instantiate (1:=Q).

      iDestruct "Hinv" as (???) "(%Henc2 & HP & #Hghost2)".
      iDestruct (fmlist_idx_agree_1 with "Hcur_state_var Hghost2") as "%Heq".
      replace (epoch0) with (epoch) by naive_solver.
      replace (ops0) with (ops) by naive_solver.
      replace (sealed) with (false) by naive_solver.

      iMod ("Hupd" with "HP") as "[HP $]".
      iModIntro.
      iExists _, _, _.
      iFrame "HP".
      iFrame "#".
      iPureIntro.
      by apply file_encodes_state_seal.
    }
    iIntros (l) "[Haof HupdQ]".
    wp_pures.
    wp_loadField.
    wp_apply (wp_AppendOnlyFile__WaitAppend with "His_aof").
    iIntros "Hl".
    iMod ("HupdQ" with "Hl") as "[HQ #Hlb]".

    wp_pures.
    wp_loadField.
    iAssert (_) with "HisMemSm" as "#HisMemSm2".
    iNamed "HisMemSm2".
    wp_loadField.
    wp_apply ("HgetState_spec" with "[$Hmemstate]").
    iIntros (??) "(Hmemstate & %HencSnap & #Hsnap_sl)".
    wp_pures.
    iApply "HΦ".
    iModIntro.
    iFrame "Hsnap_sl HQ".
    iSplitR; first done.

    iExists fname, aof_ptr, γ, γaof, _, _, _, _.
    iExists _.
    iFrame "∗#".
    iSplitR.
    {
      iPureIntro.
      by apply file_encodes_state_seal.
    }
    iPureIntro.
    rewrite app_length.
    rewrite app_length.
    rewrite replicate_length.
    simpl.
    word.
  }
  {
    wp_pures.
    wp_loadField.
    iAssert (_) with "HisMemSm" as "#HisMemSm2".
    iNamed "HisMemSm2".
    wp_loadField.
    wp_apply ("HgetState_spec" with "[$Hmemstate]").
    iIntros (??) "(Hmemstate & %HencSnap & #Hsnap_sl)".
    wp_pure1_credit "Hlc".
    wp_pures.
    iApply "HΦ".
    iFrame "Hsnap_sl".

    iDestruct (accessP with "His_aof Hdurlb Haof") as "HH".
    iMod "HH".
    iDestruct "HH" as (?) "(%HdurPrefix & %HotherPrefix & HP & HcloseP)".
    replace (durableData) with (data); last first.
    {
      apply list_prefix_eq; first done.
      apply prefix_length; done.
    }
    iMod (lc_fupd_elim_later with "Hlc HP") as "HP".
    unfold file_inv.
    iDestruct "HP" as (??? HdurPrefixEnc) "[HP #Hcurstate2]".

    iDestruct (fmlist_idx_agree_1 with "Hcur_state_var Hcurstate2") as "%Heq".
    replace (epoch0) with (epoch) by naive_solver.
    replace (ops0) with (ops) by naive_solver.
    replace (sealed) with (true) by naive_solver.

    iMod ("Hupd" with "HP") as "[HP HQ]".
    iMod ("HcloseP" with "[HP]").
    {
      iNext.
      iExists _, _, _.
      iFrame "∗#%".
    }
    iModIntro.
    iFrame "HQ".
    iSplitR; first done.

    iExists fname, aof_ptr, γ, γaof, _, _, _, _.
    iExists _.
    iFrame "∗#".
    done.
  }
Qed.

Lemma wp_recoverStateMachine data P fname smMem own_InMemoryStateMachine :
  {{{
       "Hfile_ctx" ∷ crash_borrow (fname f↦ data ∗ file_crash P data)
                    (|C={⊤}=> ∃ data', fname f↦ data' ∗ ▷ file_crash P data') ∗
        "#HisMemSm" ∷ is_InMemoryStateMachine smMem own_InMemoryStateMachine ∗
        "Hmemstate" ∷ own_InMemoryStateMachine []
  }}}
    recoverStateMachine #smMem #(LitString fname)
  {{{
        s epoch ops sealed, RET #s; own_StateMachine s epoch ops sealed P
  }}}.
Proof.
  iIntros (Φ) "Hpre HΦ".
  iNamed "Hpre".
  wp_call.
  wp_pures.

  wp_apply (wp_allocStruct).
  { repeat econstructor. }

  iIntros (s) "Hs".
  wp_pures.
  iDestruct (struct_fields_split with "Hs") as "HH".
  iNamed "HH".

  wp_loadField.

  wp_bind (FileRead _).
  iApply wpc_wp.
  instantiate (1:=True%I).
  wpc_apply (wpc_crash_borrow_open_modify with "Hfile_ctx").
  { done. }
  iSplit; first done.
  iIntros "[Hfile Hfilecrash]".
  iDestruct "Hfilecrash" as "[Hempty|Hnonempty]".
  { (* case: empty *)
    iDestruct "Hempty" as "[%HdataEmpty HP]".
    iMod (fmlist_alloc (replicate (1) (U64 0, [], false))) as (γsl_state) "Hallstates".
    set (γ:={| sl_state := γsl_state |} ).
    iMod (fmlist_get_lb with "Hallstates") as "[Hallstates #Hlb]".
    iDestruct (fmlist_lb_to_idx _ _ (length data) with "Hlb") as "#Hcurstate".
    {
      apply lookup_replicate.
      rewrite HdataEmpty.
      split; last (simpl; lia).
      done.
    }

    wpc_apply (wpc_FileRead with "[$Hfile]").
    iSplit.
    { (* case: crash while reading *)
      iIntros "Hfile".
      iSplitR; first done.
      iModIntro.
      iExists _; iFrame.
      iNext.
      iLeft.
      iFrame "∗%".
    }
    (* otherwise, no crash and we keep going *)
    iNext.
    iIntros (data_sl) "[Hfile Hdata_sl]".
    iExists (fname f↦data ∗ P 0 [] false)%I.
    iSplitL "Hfile HP".
    {
      iFrame.
    }
    iSplit.
    {
      iModIntro.
      iIntros "[? Hinv]".
      iModIntro.
      iExists _; iFrame.
      iNext.
      iLeft.
      iFrame "∗%".
    }
    iIntros "Hfile_ctx".
    iSplit; first done.

    wp_apply (wp_ref_to).
    { done. }
    iIntros (enc_ptr) "Henc".
    wp_pures.
    wp_load.

    iDestruct (is_slice_sz with "Hdata_sl") as %Hdata_sz.
    wp_apply (wp_slice_len).
    wp_pures.
    wp_if_destruct.
    2:{ (* bad case *)
      exfalso.
      rewrite HdataEmpty /= in Hdata_sz.
      replace (data_sl.(Slice.sz)) with (U64 0) in * by word.
      done.
    }

    iAssert (_) with "HisMemSm" as "#HisMemSm2".
    iNamed "HisMemSm2".
    wp_loadField.
    wp_apply ("HgetState_spec" with "[$Hmemstate]").
    iIntros (??) "(Hmemstate & %Hsnapenc & #Hsnap_sl)".
    wp_pures.
    iMod (readonly_load with "Hsnap_sl") as (?) "Hsnap_sl2".
    iDestruct (is_slice_small_sz with "Hsnap_sl2") as %Hsnap_sz.
    wp_apply (wp_slice_len).
    wp_apply (wp_NewSliceWithCap).
    { apply encoding.unsigned_64_nonneg. }
    iIntros (?) "Henc_sl".
    wp_apply (wp_ref_to).
    { done. }
    iIntros (initialContents_ptr) "HinitialContents".
    wp_pures.
    wp_apply (wp_slice_len).
    wp_load.
    wp_apply (wp_WriteInt with "Henc_sl").
    iIntros (enc_sl) "Henc_sl".
    wp_store.
    wp_load.
    wp_apply (wp_WriteBytes with "[$Henc_sl $Hsnap_sl2]").
    iIntros (enc_sl2) "[Henc_sl _]".
    rewrite replicate_0.
    wp_store.
    wp_load.
    wp_apply (wp_WriteInt with "Henc_sl").
    iIntros (enc_sl3) "Henc_sl".
    wp_store.
    wp_load.
    wp_apply (wp_WriteInt with "Henc_sl").
    iIntros (enc_sl4) "Henc_sl".
    wp_store.
    wp_load.

    wp_loadField.

    iDestruct (is_slice_to_small with "Henc_sl") as "Henc_sl".
    wp_bind (FileWrite _ _).
    iApply (wpc_wp).
    instantiate (1:=True%I).
    wpc_apply (wpc_crash_borrow_open_modify with "Hfile_ctx").
    { done. }
    iSplit; first done.
    iIntros "[Hfile HP]".
    iApply wpc_fupd.
    wpc_apply (wpc_FileWrite with "[$Hfile $Henc_sl]").
    iSplit.
    { (* case: crash while writing *)
      iIntros "[Hbefore|Hafter]".
      {
        iSplitR; first done.
        iModIntro.
        iExists _.
        iFrame.
        iNext.
        iLeft.
        iFrame. done.
      }
      {
        iSplitR; first done.
        iModIntro.
        iExists _.
        iFrame.
        iNext.
        iRight.
        iExists (U64 0), [], false.
        iFrame.
        iPureIntro.
        replace (snap_sl.(Slice.sz)) with (U64 (length snap)); last first.
        { word. }
        rewrite app_nil_l.
        rewrite -app_assoc.
        unshelve (epose proof (file_encodes_state_snapshot snap [] 0 _ Hsnapenc)  as H; done).
        simpl. lia.
      }
    }
    iNext.
    iIntros "[Hfile _]".

    set (n:=(length (((([] ++ u64_le snap_sl.(Slice.sz)) ++ snap) ++ u64_le 0%Z) ++ u64_le 0%Z))).
    iMod (fmlist_update with "Hallstates") as "[Hallstates Hallstates_lb]".
    {
      instantiate (1:=((replicate (n+1) (U64 0, [], false)))).
      rewrite replicate_S.
      simpl.
      apply prefix_cons.
      apply prefix_nil.
    }

    iDestruct (fmlist_lb_to_idx _ _ n with "Hallstates_lb") as "#Hcurstate2".
    {
      apply lookup_replicate.
      split; last lia.
      done.
    }

    iModIntro.
    evar (c:list u8).
    iExists (fname f↦ ?c ∗ file_inv γ P ?c)%I.
    iSplitL "Hfile HP".
    {
      iFrame "Hfile".
      iExists _, _, _.
      iFrame "∗#".
      iPureIntro.

      replace (snap_sl.(Slice.sz)) with (U64 (length snap)); last first.
      { word. }
      rewrite app_nil_l.
      rewrite -app_assoc.
      unshelve (epose proof (file_encodes_state_snapshot snap [] 0 _ Hsnapenc)  as H; done).
      simpl; lia.
    }
    iSplit.
    {
      iModIntro.
      iIntros "[Hfile Hinv]".
      iModIntro.
      iExists _.
      iFrame.
      iNext.
      iRight.
      iDestruct "Hinv" as (???) "[H1 [H2 _]]".
      iExists _, _, _.
      iFrame.
    }
    iIntros "Hfile_ctx".
    iSplit; first done.
    wp_pures.
    wp_apply (wp_CreateAppendOnlyFile with "[] [$Hfile_ctx]").
    {
      iModIntro.
      iIntros (?) "Hinv".
      iModIntro.
      iNext.
      iDestruct "Hinv" as (???) "(H1 & H2 & _)".
      iRight. iExists _, _, _.
      iFrame.
    }
    iIntros (aof_ptr γaof) "(His_aof & Haof & #Hdurablelb)".
    wp_storeField.

    iApply "HΦ".
    iModIntro.
    do 9 iExists _.
    iFrame "∗#%".
    iSplitR; first done.
    iSplitR; first iPureIntro.
    {
      replace (snap_sl.(Slice.sz)) with (U64 (length snap)); last first.
      { word. }
      rewrite app_nil_l.
      rewrite -app_assoc.
      unshelve (epose proof (file_encodes_state_snapshot snap [] 0 _ Hsnapenc)  as H; done).
      simpl; lia.
    }
    iSplitL; first done.
    iPureIntro.
    rewrite replicate_length.
    unfold n.
    done.
  }

  (* case: file is non-empty, so we have to recovery from it *)
  iDestruct "Hnonempty" as (???) "[%Henc HP]".

  iMod (fmlist_alloc (replicate (length data + 1) (epoch, ops, sealed))) as (γsl_state) "Hallstates".
  set (γ:={| sl_state := γsl_state |} ).

  iMod (fmlist_get_lb with "Hallstates") as "[Hallstates #Hlb]".
  iDestruct (fmlist_lb_to_idx _ _ (length data) with "Hlb") as "#Hcurstate".
  {
    apply lookup_replicate.
    split; last lia.
    done.
  }

  wpc_apply (wpc_FileRead with "[$Hfile]").
  iSplit.
  { (* case: crash while reading *)
    iIntros "Hfile".
    iSplitR; first done.
    iModIntro.
    iExists _; iFrame.
    iNext.
    iRight.
    iExists _, _, _; iFrame "∗%".
  }
  (* otherwise, no crash and we keep going *)
  iNext.
  iIntros (data_sl) "[Hfile Hdata_sl]".
  iExists (fname f↦data ∗ file_inv γ P data)%I.
  iSplitL "Hfile HP".
  {
    iFrame.
    iExists _, _, _.
    iFrame "∗#%".
  }
  iSplit.
  {
    iModIntro.
    iIntros "[? Hinv]".
    iModIntro.
    iExists _; iFrame.
    iNext.
    iDestruct "Hinv" as (???) "(H1 & H2 & _)".
    iRight.
    iExists _, _, _.
    iFrame.
  }
  iIntros "Hfile_ctx".
  iSplit; first done.

  wp_apply (wp_ref_to).
  { done. }
  iIntros (enc_ptr) "Henc".
  wp_pures.
  wp_load.

  iDestruct (is_slice_sz with "Hdata_sl") as %Hdata_sz.
  wp_apply (wp_slice_len).
  wp_pures.
  wp_if_destruct.
  { (* bad case *)
    exfalso.
    apply file_encodes_state_nonempty in Henc.
    rewrite Heqb in Hdata_sz.
    assert (length data = 0%nat) by done.
    word.
  }

  wp_apply (wp_CreateAppendOnlyFile with "[] [$Hfile_ctx]").
  {
    iModIntro.
    iIntros (?) "Hinv".
    iModIntro.
    iNext.
    iDestruct "Hinv" as (???) "(H1 & H2 & _)".
    iRight.
    iExists _, _, _.
    iFrame.
  }
  iIntros (aof_ptr γaof) "(His_aof & Haof & #Hdurablelb)".
  wp_storeField.

  wp_apply (wp_ref_of_zero).
  { done. }
  iIntros (snapLen_ptr) "HsnapLen".
  wp_pures.
  wp_apply (wp_ref_of_zero).
  { done. }
  iIntros (snap_ptr) "Hsnap".
  wp_pures.
  wp_load.
  iDestruct (is_slice_to_small with "Hdata_sl") as "Hdata_sl".
  pose proof Henc as Henc2.
  destruct Henc as (snap_ops & snap & rest_ops & rest_ops_bytes & sealed_bytes & Henc).
  destruct Henc as (Hops & Hsnap_enc & Hsealedbytes & Hrest_ops_len & Henc).
  destruct Henc as (Hop_bytes & Hops_len & HdataEnc).
  rewrite HdataEnc.

  wp_apply (wp_ReadInt with "[$Hdata_sl]").
  iIntros (data_sl2) "Hdata_sl".
  wp_pures.
  wp_store.
  wp_store.
  wp_load.
  wp_load.
  iDestruct "Hdata_sl" as "[Hdata_sl Hdata_sl2]".

  assert (int.nat (length snap) = length snap) as HsnapNoOverflow.
  { rewrite HdataEnc in Hdata_sz. rewrite ?app_length in Hdata_sz. word. }
  wp_apply (wp_SliceSubslice_small with "Hdata_sl").
  {
    rewrite app_length.
    split.
    { word. }
    { word. }
  }
  iIntros (snap_sl) "Hsnap_sl".
  rewrite -> subslice_drop_take by word.
  rewrite drop_0.
  rewrite Nat.sub_0_r.
  replace (int.nat (length snap)) with (length snap).
  rewrite take_app.
  wp_store.

  wp_load.
  wp_apply (wp_slice_len).
  wp_pures.
  iDestruct (is_slice_small_sz with "Hdata_sl2") as %Hdata_sl2_sz.
  wp_load.
  wp_load.

  wp_apply (wp_SliceSubslice_small with "Hdata_sl2").
  {
    rewrite -Hdata_sl2_sz.
    split.
    {
      rewrite app_length.
      word.
    }
    { word. }
  }
  iIntros (data_sl3) "Hdata_sl".

  rewrite -Hdata_sl2_sz.
  rewrite -> subslice_drop_take; last first.
  {
    rewrite app_length; word.
  }
  replace (int.nat (length snap)) with (length snap).
  rewrite drop_app.
  iEval (rewrite app_length) in "Hdata_sl".
  replace (length snap +
                     length
                       (u64_le epoch ++
                        u64_le (length snap_ops) ++ concat rest_ops_bytes ++ sealed_bytes) - length snap)%nat with (
                     length
                       (u64_le epoch ++
                        u64_le (length snap_ops) ++ concat rest_ops_bytes ++ sealed_bytes))
    by word.
  rewrite take_ge; last first.
  {
    done.
  }
  wp_store.

  iAssert (_) with "HisMemSm" as "#HisMemSm2".
  iNamed "HisMemSm2".
  wp_load.
  wp_loadField.
  wp_loadField.

  iMod (readonly_alloc (is_slice_small snap_sl byteT 1 snap) with "[Hsnap_sl]") as "#Hsnap_sl".
  {
    simpl.
    iFrame.
  }
  wp_apply ("HsetState_spec" with "[$Hmemstate $Hsnap_sl]").
  {
    done.
  }
  iIntros "Hmemstate".
  wp_pures.

  wp_load.
  wp_apply (wp_ReadInt with "Hdata_sl").
  iIntros (data_sl4) "Hdata_sl".
  wp_pures.
  wp_storeField.
  wp_store.

  wp_load.
  wp_apply (wp_ReadInt with "Hdata_sl").
  iIntros (data_sl5) "Hdata_sl".
  wp_pures.
  wp_storeField.
  wp_store.
  wp_pures.

  (* loop invariant *)
  iAssert (
      ∃ rest_ops_sl (numOpsApplied:nat) q,
      "Henc" ∷ enc_ptr ↦[slice.T byteT] (slice_val rest_ops_sl) ∗
      "Hdata_sl" ∷ is_slice_small rest_ops_sl byteT q (concat (drop numOpsApplied rest_ops_bytes) ++ sealed_bytes) ∗
      "Hmemstate" ∷ own_InMemoryStateMachine (snap_ops ++ (take numOpsApplied rest_ops)) ∗
      "HnextIndex" ∷ s ↦[StateMachine :: "nextIndex"] #(length snap_ops + numOpsApplied)%nat ∗
      "%HnumOpsApplied_le" ∷ ⌜numOpsApplied <= length rest_ops⌝
    )%I with "[Henc Hdata_sl Hmemstate nextIndex]" as "HH".
  {
    iExists _, 0%nat, _.
    iFrame.
    rewrite take_0.
    rewrite app_nil_r.
    rewrite Nat.add_0_r.
    iFrame.
    iPureIntro.
    word.
  }

  wp_forBreak.
  iNamed "HH".
  wp_pures.

  wp_load.
  iDestruct (is_slice_small_sz with "Hdata_sl") as %Hrest_data_sz.
  wp_apply (wp_slice_len).
  wp_if_destruct.
  { (* there's enough bytes to make up an entire operation *)
    wp_apply (wp_ref_of_zero).
    { done. }
    iIntros (opLen) "HopLen".
    wp_pures.
    wp_load.

    destruct (drop numOpsApplied rest_ops_bytes) as [ | nextOp_bytes new_rest_ops_bytes] eqn:X.
    {
      exfalso.
      simpl in Hrest_data_sz.
      assert (1 < length sealed_bytes) by word.
      rewrite Hsealedbytes /= in H.
      destruct sealed.
      { simpl in H. lia. }
      { simpl in H. lia. }
    }
    assert (length rest_ops_bytes <= numOpsApplied ∨ numOpsApplied < length rest_ops) as [Hbad | HappliedLength] by word.
    {
      exfalso.
      rewrite -X in Hrest_data_sz.
      assert (length rest_ops_bytes ≤ numOpsApplied)%nat by word.
      rewrite drop_ge /= in Hrest_data_sz; last done.
      assert (1 < length sealed_bytes) by word.
      rewrite Hsealedbytes in H0.
      destruct sealed.
      { simpl in H0; lia. }
      { simpl in H0; lia. }
    }

    specialize (Hop_bytes numOpsApplied HappliedLength).
    destruct Hop_bytes as (op & op_len_bytes & op_bytes & Hop_bytes).
    destruct Hop_bytes as (Hrest_ops_lookup & Hrest_ops_bytes_lookup & Henc & Hoplenbytes).

    replace (nextOp_bytes) with (u64_le (length op_bytes) ++ op_bytes); last first.
    {
      erewrite drop_S  in X; eauto.
      inversion X; subst; auto.
    }
    iEval (rewrite concat_cons) in "Hdata_sl".
    rewrite -app_assoc.
    rewrite -app_assoc.
    wp_apply (wp_ReadInt with "[$Hdata_sl]").
    iIntros (rest_ops_sl2) "Hdata_sl".
    wp_pures.
    wp_store.
    wp_store.
    wp_load.
    wp_load.

    (* split the slice into two parts; copy/pasted from above *)
    iDestruct "Hdata_sl" as "[Hdata_sl Hdata_sl2]".
    assert (int.nat (length op_bytes) = length op_bytes).
    { apply (take_drop_middle) in Hrest_ops_bytes_lookup.
      rewrite -Hrest_ops_bytes_lookup ?concat_app in HdataEnc.
      rewrite HdataEnc in Hdata_sz. clear -Hdata_sz. rewrite ?app_length in Hdata_sz.
      word.
    }
    wp_apply (wp_SliceSubslice_small with "Hdata_sl").
    {
      rewrite app_length.
      split.
      { word. }
      { word. }
    }
    iIntros (op_sl) "Hop_sl".
    rewrite -> subslice_drop_take by word.
    rewrite drop_0.
    rewrite Nat.sub_0_r.
    replace (int.nat (length op_bytes)) with (length op_bytes).
    rewrite take_app.

    wp_pures.
    wp_load.
    wp_apply (wp_slice_len).
    wp_pures.
    wp_load.
    wp_load.

    clear Hdata_sl2_sz.
    iDestruct (is_slice_small_sz with "Hdata_sl2") as %Hdata_sl2_sz.
    wp_apply (wp_SliceSubslice_small with "Hdata_sl2").
    {
      rewrite -Hdata_sl2_sz.
      split.
      {
        rewrite app_length.
        word.
      }
      { word. }
    }
    iIntros (rest_ops_sl3) "Hdata_sl".
    wp_store.
    wp_loadField.
    wp_loadField.

    rewrite -Hdata_sl2_sz.
    rewrite -> subslice_drop_take; last first.
    {
      rewrite app_length; word.
    }
    replace (int.nat (length op_bytes)) with (length op_bytes).
    rewrite drop_app.
    iEval (rewrite app_length) in "Hdata_sl".
    replace ((length op_bytes + length (concat new_rest_ops_bytes ++ sealed_bytes) -
                     length op_bytes))%nat with
      (length (concat new_rest_ops_bytes ++ sealed_bytes)) by word.
    iEval (rewrite take_ge) in "Hdata_sl"; last first.
    (* done splitting slices into two parts *)

    iMod (readonly_alloc (is_slice_small op_sl byteT 1 op_bytes) with "[Hop_sl]") as "#Hop_sl".
    {
      simpl.
      iFrame.
    }
    wp_apply ("HapplyVolatile_spec" with "[$Hmemstate $Hop_sl]").
    { done. }
    iIntros (? ?) "[Hmemstate _]".
    wp_pures.
    wp_loadField.
    wp_apply (std_proof.wp_SumAssumeNoOverflow).
    iIntros (HnextIndexOverflow).
    wp_storeField.
    iModIntro.
    iLeft.
    iSplitR; first done.
    iFrame "∗#%".
    iExists _, (numOpsApplied + 1)%nat, (q/2)%Qp.
    iFrame.
    iSplitL "Hdata_sl".
    {
      iApply to_named.
      iExactEq "Hdata_sl".
      f_equal.
      f_equal.
      rewrite -drop_drop.
      rewrite X.
      rewrite skipn_cons.
      rewrite drop_0.
      done.
    }
    iSplitL "Hmemstate".
    {
      iApply to_named.
      iExactEq "Hmemstate".
      f_equal.
      rewrite -app_assoc.
      f_equal.
      rewrite (take_more); last first.
      { word. }
      f_equal.
      apply list_eq.
      intros.
      destruct i.
      {
        simpl.
        rewrite lookup_take; last lia.
        rewrite lookup_drop.
        rewrite Nat.add_0_r.
        done.
      }
      {
        simpl.
        rewrite lookup_take_ge; last lia.
        done.
      }
    }
    iSplitL "HnextIndex".
    {
      iApply to_named.
      iExactEq "HnextIndex".

      repeat f_equal.
      apply word.unsigned_inj; auto.
      rewrite ?word.unsigned_add /=.
      rewrite -[a in a = _]unsigned_U64.
      f_equal.
      replace (Z.of_nat (length snap_ops + (numOpsApplied + 1)))%Z with
        (Z.of_nat (length snap_ops + numOpsApplied) + int.Z (U64 1))%Z; last first.
      { replace (int.Z 1%Z) with 1%Z.
        { clear. f_equal. lia. }
        rewrite //=.
      }
      clear.
      remember (Z.of_nat (length snap_ops + numOpsApplied)) as x.
      { rewrite /U64.
        rewrite ?word.ring_morph_add. f_equal.
        rewrite word.of_Z_unsigned. auto.
      }
    }
    iPureIntro.
    word.
  }
  (* done with loop *)
  assert (numOpsApplied = length rest_ops_bytes ∨ numOpsApplied < length rest_ops) as [ | Hbad] by word.
  2:{
    exfalso.
    assert (length (drop numOpsApplied rest_ops_bytes) > 0).
    { rewrite drop_length. lia. }
    edestruct (Hop_bytes (numOpsApplied)) as (op&op_len_bytes&op_bytes&Hlookup1&Hlookup2&Henc&Hlen_bytes).
    { lia. }
    erewrite drop_S in Hrest_data_sz; eauto.
    rewrite /= ?app_length in Hrest_data_sz.
    rewrite Hlen_bytes u64_le_length in Hrest_data_sz.
    assert (int.nat (rest_ops_sl.(Slice.sz)) <= 1).
    { word. }
    lia.
  }

  iDestruct (is_slice_small_sz with "Hdata_sl") as %Hdata_sl_sz.
  iRight.
  iModIntro.
  iSplitR; first done.
  wp_pures.
  wp_load.
  wp_apply (wp_slice_len).
  wp_if_destruct.
  { (* sealed = true *)
    wp_storeField.
    destruct sealed.
    2:{
      exfalso.
      rewrite List.skipn_all /= ?Hsealedbytes /= in Hdata_sl_sz; last by lia.
      word.
    }
    iApply "HΦ".
    iModIntro.
    do 9 iExists _.
    iFrame "∗#%".
    rewrite take_ge; last word.
    iEval (rewrite H) in "HnextIndex".
    rewrite -Hrest_ops_len.
    iSplitL "HnextIndex".
    { repeat rewrite app_length. iFrame. }
    iSplitR.
    {
      iPureIntro.
      rewrite -HdataEnc.
      rewrite -Hops.
      done.
    }
    iSplitR.
    {
      iPureIntro.
      rewrite -Hops.
      word.
    }
    rewrite -Hops.
    iFrame "Hcurstate".
    rewrite replicate_length.
    iPureIntro.
    done.
  }
  (* sealed = false *)
  wp_pures.
  destruct sealed.
  {
    exfalso.
    assert (int.nat rest_ops_sl.(Slice.sz) = 0%nat).
    { assert (int.Z 0 = 0%Z) as Heq_Z0 by auto.
      rewrite Heq_Z0 in Heqb1. word.
    }
    rewrite -Hdata_sl_sz in H0.
    rewrite app_length in H0.
    rewrite Hsealedbytes /= in H0.
    word.
  }

  iModIntro.
  iApply "HΦ".
  do 9 iExists _.
  iFrame "∗#%".
  rewrite take_ge; last word.
  iEval (rewrite H) in "HnextIndex".
  rewrite -Hrest_ops_len.
  iSplitL "HnextIndex".
  { repeat rewrite app_length. iFrame. }
  iSplitR; first done.
  iSplitR.
  {
    iPureIntro.
    rewrite -HdataEnc.
    rewrite -Hops.
    done.
  }
  iSplitR.
  {
    iPureIntro.
    rewrite -Hops.
    word.
  }
  rewrite -Hops.
  iFrame "Hcurstate".
  rewrite replicate_length.
  iPureIntro.
  done.
Admitted.

Notation own_Server_ghost := (own_Server_ghost (pb_record:=sm_record)).
Notation wp_MakeServer := (wp_MakeServer (pb_record:=sm_record)).

Definition simplelog_P γ γsrv := file_crash (own_Server_ghost γ γsrv).

Definition simplelog_pre γ γsrv fname :=
  (|C={⊤}=> ∃ data, fname f↦ data ∗ ▷ simplelog_P γ γsrv data)%I.

Lemma wp_MakePbServer smMem own_InMemoryStateMachine fname γ data γsrv :
  let P := (own_Server_ghost γ γsrv) in
  sys_inv γ -∗
  {{{
       "Hfile_ctx" ∷ crash_borrow (fname f↦ data ∗ file_crash P data)
                    (|C={⊤}=> ∃ data', fname f↦ data' ∗ ▷ file_crash P data') ∗
       "#HisMemSm" ∷ is_InMemoryStateMachine smMem own_InMemoryStateMachine ∗
       "Hmemstate" ∷ own_InMemoryStateMachine []
  }}}
    MakePbServer #smMem #(LitString fname)
  {{{
        s, RET #s; pb_definitions.is_Server s γ γsrv
  }}}
.
Proof.
  (*
  iIntros (?) "#Hsys".
  iIntros (Φ Φc) "!# Hpre HΦ".
  iApply wpc_cfupd.

  iNamed "Hpre".
  iDestruct "Hcrash" as (?) "[Hfile Hcrash]".
  wpc_apply (wpc_crash_borrow_inits with "[] [Hfile Hcrash] []").
  { admit. }
  { iAccu. }
  {
    iModIntro.
    instantiate (1:=(|C={⊤}=> ∃ data', fname f↦ data' ∗ ▷ file_crash P data')).
    iIntros "[H1 H2]".
    iModIntro.
    iExists _.
    iFrame.
  }
  iIntros "Hfile_ctx".

  Search wpc.
  wpc_apply (wpc_crash_mono _ _ _ _ _ (True%I) with "[HΦ]").
  {
    iLeft in "HΦ".
    iIntros "_ Hupd".
    iMod "Hupd" as (?) "[H1 H2]".
    iModIntro.
    iApply "HΦ".
    iExists _.
    iFrame.
  }
  iApply wp_wpc.
 *)
  iIntros (?) "#Hsys".
  iIntros (Φ) "!# Hpre HΦ".
  iNamed "Hpre".

  wp_lam.
  wp_pures.
  wp_apply (wp_recoverStateMachine with "[-HΦ]").
  { iFrame "∗#". }
  iIntros (????) "Hsm".
  wp_pures.

  wp_apply (wp_allocStruct).
  { repeat econstructor. }
  iIntros (sm) "HpbSm".
  iDestruct (struct_fields_split with "HpbSm") as "HH".
  iNamed "HH".
  iMod (readonly_alloc_1 with "StartApply") as "#HstartApply".
  iMod (readonly_alloc_1 with "GetStateAndSeal") as "#HgetState".
  iMod (readonly_alloc_1 with "SetStateAndUnseal") as "#HsetState".

  iNamed "Hsm".
  wp_loadField.
  wp_loadField.
  wp_loadField.

  iAssert (own_StateMachine s epoch ops sealed P) with "[-HΦ]" as "Hsm".
  {
    do 9 iExists _.
    iFrame "∗#%".
  }

  wp_apply (wp_MakeServer _ (own_StateMachine s)  with "[Hsm]").
  {
    iFrame "Hsm Hsys".
    iSplitL; last first.
    {
      iPureIntro.
      destruct Henc as (?&?&?&?&?&?). word.
    }
    iExists _, _, _.
    iFrame "#".
    iSplitL.
    { (* apply spec *)
      clear Φ.
      iIntros (?????? Φ) "!#".
      iIntros "(%HopEncoding & #Hop_sl & Hupd & Hsm) HΦ".
      wp_lam.
      wp_apply (wp_StateMachine__apply with "[$Hsm $Hop_sl Hupd]").
      {
        iFrame "%".
        instantiate (1:=Q).
        iIntros "H1".
        iMod (fupd_mask_subseteq (↑pbN)) as "Hmask".
        {
          enough ((↑aofN:coPset) ## ↑pbN) by set_solver.
          by apply ndot_ne_disjoint.
        }
        iMod ("Hupd" with "H1").
        iMod "Hmask".
        iModIntro.
        iFrame.
      }
      iFrame.
    }
    iSplitL.
    { (* set state spec *)
      clear Φ.
      iIntros (???????? Φ) "!#".
      iIntros "(%HopEncoding & #Hop_sl & Hupd & Hsm) HΦ".
      wp_lam.
      wp_pures.
      wp_apply (wp_setStateAndUnseal with "[$Hsm $Hop_sl Hupd]").
      {
        iFrame "%".
        iSplit.
        { iPureIntro. admit. (* Must assume snap encoding enforces this bound? *) }
        iIntros "H1".
        instantiate (1:=Q).
        iMod (fupd_mask_subseteq (↑pbN)) as "Hmask".
        {
          enough ((↑aofN:coPset) ## ↑pbN) by set_solver.
          by apply ndot_ne_disjoint.
        }
        iMod ("Hupd" with "H1").
        iMod "Hmask".
        iModIntro.
        iFrame.
      }
      iIntros.
      wp_pures.
      iModIntro.
      iApply "HΦ".
      iFrame.
    }
    { (* get state spec *)
      clear Φ.
      iIntros (???? Φ) "!#".
      iIntros "(Hsm & Hupd) HΦ".
      wp_lam.
      wp_pures.
      wp_apply (wp_getStateAndSeal with "[$Hsm Hupd]").
      {
        iFrame "%".
        instantiate (1:=Q).
        iIntros "H1".
        iMod (fupd_mask_subseteq (↑pbN)) as "Hmask".
        {
          enough ((↑aofN:coPset) ## ↑pbN) by set_solver.
          by apply ndot_ne_disjoint.
        }
        iMod ("Hupd" with "H1").
        iMod "Hmask".
        iModIntro.
        iFrame.
      }
      iIntros.
      iApply "HΦ".
      iFrame.
    }
  }
  done.
Admitted.

End proof.
