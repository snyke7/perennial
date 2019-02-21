From iris.algebra Require Import auth gmap list.
Require Export CSL.Refinement.
Require Import AtomicPairAPI AtomicPair.ImplShadow ExMach.WeakestPre ExMach.RefinementAdequacy.
Require Import AtomicPair.Helpers.
Unset Implicit Arguments.

Existing Instance from_exist_left_sep.

Local Ltac destruct_einner H :=
  iDestruct H as (? (?&?) (?&?)) ">(Hown1&Hown2&Hown3&Hsource&Hmap)";
  iDestruct "Hmap" as "(Hptr&Hcase)";
  try (iDestruct (ghost_var_agree with "Hown1 [$]") as %?; subst; []);
  try (iDestruct (ghost_var_agree with "Hown2 [$]") as %Hp; inversion_clear Hp; subst; []);
  try (iDestruct (ghost_var_agree with "Hown3 [$]") as %Hp; inversion_clear Hp; subst; []).

Set Default Proof Using "Type".
Section refinement_triples.
  Context `{!exmachG Σ, lockG Σ, !@cfgG (AtomicPair.Op) (AtomicPair.l) Σ,
            !inG Σ (authR (optionUR (exclR (prodC natC natC)))),
            !inG Σ (authR (optionUR (exclR natC)))}.
  Context (ρ : thread_pool AtomicPair.Op * AtomicPair.l.(State)).

  Import ExMach.

  (* TODO: this should work, but the invariant is too global: ideally,
     most threads should not care about the value in the non-pointed to
     copy, and a writer who holds the lock should be able to modify it freely
     without opening this invariant up prior to updating the pointer *)
  Definition ptr_map (ptr_val : nat) (pcurr: nat * nat) (pother: nat * nat) :=
    (ptr_addr d↦ ptr_val ∗
     (read_addrs ptr_val).1 d↦ pcurr.1 ∗
     (read_addrs ptr_val).2 d↦ pcurr.2 ∗
     (write_addrs ptr_val).1 d↦ pother.1 ∗
     (write_addrs ptr_val).2 d↦ pother.2)%I.

  Definition ExecInner γ1 γ2 γ3 :=
    (∃ (ptr_val : nat) (pcurr: nat * nat) (pother: nat * nat),
        own γ1 (● (Excl' ptr_val))
            ∗ own γ2 (● (Excl' pcurr))
            ∗ own γ3 (● (Excl' pother))
            ∗ source_state pcurr ∗
            ptr_map ptr_val pcurr pother)%I.


  (* Holding the lock guarantees the value of the atomic pair/pointer will not
     change out from underneath you -- this is enforced by granting ownership of
     appropriate ghost variables *)
  Definition ExecLockInv γ1 γ2 γ3 :=
    (∃ ptr_val (pcurr : nat * nat) (pother: nat * nat),
        own γ1 (◯ (Excl' ptr_val))
            ∗ own γ2 (◯ (Excl' pcurr))
            ∗ own γ3 (◯ (Excl' pother))
    )%I.

  (* Post-crash, pre recovery we know the ptr mapping is in a good state w.r.t the
     abstract state, and the lock must have been reset 0 *)

  Definition CrashInner :=
    (∃ (ptr_val : nat) (pcurr: nat * nat) pother,
        source_state pcurr ∗ ptr_map ptr_val pcurr pother ∗ lock_addr m↦ 0)%I.

  Definition lN : namespace := (nroot.@"lock").
  Definition iN : namespace := (nroot.@"inner").

  Definition ExecInv :=
    (source_ctx ρ ∗ ∃ γlock γ1 γ2 γ3, is_lock lN γlock lock_addr (ExecLockInv γ1 γ2 γ3)
                                           ∗ inv iN (ExecInner γ1 γ2 γ3))%I.
  Definition CrashInv := (source_ctx ρ ∗ inv iN CrashInner)%I.


  Lemma read_of_swap ptr_val :
    (read_addrs (swap_ptr ptr_val)) = write_addrs ptr_val.
  Proof. destruct ptr_val => //=. Qed.

  Lemma write_of_swap ptr_val :
    (write_addrs (swap_ptr ptr_val)) = read_addrs ptr_val.
  Proof. destruct ptr_val => //=. Qed.

  Lemma write_refinement {T} j K `{LanguageCtx AtomicPair.Op unit T AtomicPair.l K} p:
    {{{ j ⤇ K (Call (AtomicPair.Write p)) ∗ ExecInv }}} write p {{{ v, RET v; j ⤇ K (Ret v) }}}.
  Proof.
    iIntros (Φ) "(Hj&#Hsource_inv&Hinv) HΦ".
    iDestruct "Hinv" as (γlock γ1 γ2 γ3) "(#Hlockinv&#Hinv)".
    wp_bind. iApply (wp_lock with "[$]").
    iIntros "!> (Hlocked&HEL)".
    iDestruct "HEL" as (ptr_val pcurr pother) "(Hptr_ghost&Hpair_ghost&Hother_ghost)".
    wp_bind.
    iInv "Hinv" as "H".
    destruct_einner "H".
    iApply (wp_read_disk with "[$]"). iIntros "!> Haddr".
    iModIntro; iExists _, _, _; iFrame.
    destruct p as (new_fst&new_snd).
    wp_bind.
    (* iInv fails for mysterious type class reasons that I cannot debug *)
    iApply wp_atomic.
    iMod (inv_open with "Hinv") as "(H&Hclo)"; first by set_solver+; iModIntro.
    destruct_einner "H".

    iDestruct "Hcase" as "(?&?&Hfst&Hsnd)".
    iModIntro.
    iApply (wp_write_disk with "Hfst"). iIntros "!> Hfst".
    iMod (ghost_var_update γ3 (new_fst, n2) with "Hown3 [$]") as "(Hown3&Hother_ghost)".
    iMod ("Hclo" with "[-Hj HΦ Hlocked Hptr_ghost Hpair_ghost Hother_ghost]").
    { iModIntro. iExists ptr_val. simpl. iExists _, _; iFrame.
      simpl. iFrame. }

    iModIntro.
    wp_bind.
    iInv "Hinv" as "H".
    destruct_einner "H".
    iDestruct "Hcase" as "(Ho1&Ho2&Hfst&Hsnd)".
    iApply (wp_write_disk with "Hsnd"). iIntros "!> Hsnd".
    iMod (ghost_var_update γ3 (new_fst, new_snd) with "Hown3 [$]") as "(Hown3&Hother_ghost)".
    iModIntro; iExists _, _; iFrame.
    simpl.
    iExists (_, _). iFrame.

    (* iInv fails for mysterious type class reasons that I cannot debug *)
    wp_bind.
    iApply wp_atomic.
    iMod (inv_open with "Hinv") as "(H&Hclo)"; first by set_solver+; iModIntro.
    destruct_einner "H".
    iModIntro.
    iMod (ghost_var_update γ1 (swap_ptr ptr_val) with "Hown1 [$]") as "(Hown1&Hptr_ghost)".
    iMod (ghost_var_update γ2 (new_fst, new_snd) with "Hown2 [$]") as "(Hown2&Hpair_ghost)".
    iMod (ghost_var_update γ3 (n, n0) with "Hown3 [$]") as "(Hown3&Hother_ghost)".
    iMod (ghost_step_lifting with "Hj Hsource_inv Hsource") as "(Hj&Hsource&_)".
    { do 2 eexists; split; last by eauto. econstructor. }
    { solve_ndisj. }

    iApply (wp_write_disk with "Hptr"). iIntros "!> Hsnd".
    iMod ("Hclo" with "[-Hj HΦ Hlocked Hptr_ghost Hpair_ghost Hother_ghost]").
    { iModIntro. iExists (swap_ptr ptr_val). simpl. iExists _, _; iFrame.
      iFrame. iDestruct "Hcase" as "(Ho1&Ho2&Hfst'&Hsnd')".
      rewrite ?read_of_swap ?write_of_swap; iFrame.
    }

    iModIntro.
    iApply (wp_unlock with "[-HΦ Hj]"); iFrame.
    { iFrame "Hlockinv". iExists _, _, _. iFrame. }
    iIntros "!> _". by iApply "HΦ".
  Qed.

  Lemma read_refinement {T} j K `{LanguageCtx AtomicPair.Op (nat*nat) T AtomicPair.l K}:
    {{{ j ⤇ K (Call (AtomicPair.Read)) ∗ ExecInv }}} read {{{ v, RET v; j ⤇ K (Ret v) }}}.
  Proof.
    iIntros (Φ) "(Hj&#Hsource_inv&Hinv) HΦ".
    iDestruct "Hinv" as (γlock γ1 γ2 γ3) "(#Hlockinv&#Hinv)".
    wp_bind. iApply (wp_lock with "[$]").
    iIntros "!> (Hlocked&HEL)".
    iDestruct "HEL" as (ptr_val pcurr pother) "(Hptr_ghost&Hpair_ghost&Hother_ghost)".
    wp_bind.
    iInv "Hinv" as "H".
    destruct_einner "H".
    iApply (wp_read_disk with "[$]"). iIntros "!> Haddr".
    iModIntro; iExists _, _, _; iFrame.
    wp_bind.
    iInv "Hinv" as "H".
    destruct_einner "H".
    iDestruct "Hcase" as "(Hfst&Hsnd&?&?)".
    iApply (wp_read_disk with "Hfst"). iIntros "!> Hfst".
    iModIntro; iExists _, _, _; iFrame.
    wp_bind.
    iInv "Hinv" as "H".
    destruct_einner "H".
    iDestruct "Hcase" as "(Hfst&Hsnd&?&?)".
    iApply (wp_read_disk with "Hsnd"). iIntros "!> Hsnd".
    iMod (ghost_step_lifting with "Hj Hsource_inv Hsource") as "(Hj&Hsource&_)".
    { do 2 eexists; split; last by eauto. econstructor. }
    { solve_ndisj. }

    iModIntro; iExists _, _, _; iFrame.
    wp_bind.
    iApply (wp_unlock with "[-HΦ Hj]"); iFrame.
    { iFrame "Hlockinv". iExists _, _, _. iFrame. }
    iIntros "!> _". simpl.
    wp_ret. by iApply "HΦ".
  Qed.

  Lemma init_mem_split:
    (([∗ map] i↦v ∈ init_zero, i m↦ v) -∗ lock_addr m↦ 0)%I.
  Proof.
    iIntros "Hmem".
    rewrite (big_opM_delete _ _ 0 0); last first.
    { rewrite /ExMach.mem_state. apply init_zero_lookup_lt_zero. rewrite /size. lia. }
    iDestruct "Hmem" as "(?&_)".
    iFrame.
  Qed.

  Lemma init_disk_split:
    (([∗ map] i↦v ∈ init_zero, i d↦ v)
       -∗ ptr_addr d↦ 0 ∗ copy0_fst d↦ 0 ∗ copy0_snd d↦ 0
          ∗ copy1_fst d↦ 0 ∗ copy1_snd d↦ 0)%I.
  Proof.
    iIntros "Hdisk".
    iPoseProof (disk_ptr_iter_split_aux O 4 with "Hdisk") as "H".
    { rewrite /size. lia. }
    iDestruct "H" as "($&_)".
  Qed.

End refinement_triples.

Section refinement.

  Definition helperΣ : gFunctors := #[GFunctor (authR (optionUR (exclR (natC))));
                                       GFunctor (authR (optionUR (exclR (prodC natC natC))))].
  Instance subG_helperΣ : subG helperΣ Σ → inG Σ (authR (optionUR (exclR (natC)))).
  Proof. solve_inG. Qed.
  Instance subG_helperΣ' : subG helperΣ Σ → inG Σ (authR (optionUR (exclR (prodC natC natC)))).
  Proof. solve_inG. Qed.

  Definition myΣ : gFunctors := #[Adequacy.exmachΣ; @cfgΣ AtomicPair.Op AtomicPair.l; lockΣ; helperΣ].
  Existing Instance subG_cfgPreG.

  Definition init_absr σ1a σ1c :=
    ExMach.l.(initP) σ1c ∧ AtomicPair.l.(initP) σ1a.


  Import ExMach.
  Lemma exmach_crash_refinement_seq {T} σ1c σ1a (es: proc_seq AtomicPair.Op T) :
    init_absr σ1a σ1c →
    ¬ proc_exec_seq AtomicPair.l es (rec_singleton (Ret ())) σ1a Err →
    ∀ σ2c res, ExMach.l.(proc_exec_seq) (compile_proc_seq ImplShadow.impl es)
                                        (rec_singleton recv) σ1c (Val σ2c res) →
    ∃ σ2a, AtomicPair.l.(proc_exec_seq) es (rec_singleton (Ret tt)) σ1a (Val σ2a res).
  Proof.
    eapply (exmach_crash_refinement_seq) with
        (Σ := myΣ)
        (exec_inv := fun H1 H2 => (∃ ρ, @ExecInv myΣ H2 _ H1 _ _ ρ)%I)
        (exec_inner := fun H1 H2 => (∃ v, lock_addr m↦ v ∗
            (∃ γ1 γ2 γ3, (⌜ v = 0  ⌝ -∗ @ExecLockInv myΣ _ _ γ1 γ2 γ3) ∗ @ExecInner myΣ H2 H1 _ _ γ1 γ2 γ3))%I)
        (crash_inner := fun H1 H2 => (@CrashInner myΣ H2 H1)%I)
        (crash_param := fun H1 H2 => unit)
        (crash_inv := fun H1 H2 _ =>(∃ ρ, @CrashInv myΣ H2 H1 ρ)%I)
        (crash_starter := fun H1 H2 _ => True%I)
        (E := nclose sourceN).
    { apply _. }
    { apply _. }
    { intros. apply _. }
    { intros. apply _. }
    { set_solver+. }
    { intros. iIntros "(?&H)". iDestruct "H" as (ρ) "H". destruct op.
      - iApply (write_refinement with "[$]"). eauto.
      - iApply (read_refinement with "[$]"). eauto.
    }
    { intros. iIntros "H". iDestruct "H" as (ρ) "(?&?)". eauto. }
    { intros. iIntros "(H&_)". iDestruct "H" as (ρ) "(#Hctx&#Hinv)".
      wp_ret. iInv "Hinv" as (ptr_val pcurr pother) ">(?&Hcase&?)" "_".
      iMod (own_alloc (● (Excl' ptr_val) ⋅ ◯ (Excl' ptr_val))) as (γ1) "[Hauth_ptr Hfrag_ptr]".
      { apply auth_valid_discrete_2; split; eauto. econstructor. }
      iMod (own_alloc (● (Excl' pcurr) ⋅ ◯ (Excl' pcurr))) as (γ2) "[Hauth_curr Hfrag_curr]".
      { by eauto. }
      iMod (own_alloc (● (Excl' pother) ⋅ ◯ (Excl' pother))) as (γ3) "[Hauth_other Hfrag_other]".
      { by eauto. }
      iApply (fupd_mask_weaken _ _).
      { solve_ndisj. }
      iExists pcurr, pcurr. iFrame.
      iSplitL "".
      { iPureIntro; econstructor. }
      iClear "Hctx Hinv".
      iIntros (???) "(#Hctx&Hstate)".
      iModIntro. iExists _. iFrame. iExists γ1, γ2, γ3.
      iSplitL "Hfrag_ptr Hfrag_curr Hfrag_other"; iIntros; iExists _, _, _; iFrame.
    }
    { intros ?? (H&?). inversion H. subst. eapply ExMach.init_state_wf. }
    { intros ??? (H&Hinit) ??. inversion H. inversion Hinit. subst.
      iIntros "(Hmem&Hdisk&#?&Hstate)".
      iMod (own_alloc (● (Excl' 0) ⋅ ◯ (Excl' 0))) as (γ1) "[Hauth_ptr Hfrag_ptr]".
      { apply auth_valid_discrete_2; split; eauto. econstructor. }
      iMod (own_alloc (● (Excl' (0, 0)) ⋅ ◯ (Excl' (0, 0)))) as (γ2) "[Hauth_curr Hfrag_curr]".
      { apply auth_valid_discrete_2; split; eauto. econstructor. }
      iMod (own_alloc (● (Excl' (0, 0)) ⋅ ◯ (Excl' (0, 0)))) as (γ3) "[Hauth_other Hfrag_other]".
      { apply auth_valid_discrete_2; split; eauto. econstructor. }
      iPoseProof (init_mem_split with "Hmem") as "?".
      iPoseProof (init_disk_split with "Hdisk") as "(?&?&?&?&?)".
      iModIntro. iExists _. iFrame. iExists γ1, γ2, γ3.
      iSplitL "Hfrag_ptr Hfrag_curr Hfrag_other"; iIntros; iExists _, _, _; iFrame.
      simpl. iFrame.
    }
    { intros. iIntros "H". iDestruct "H" as (ρ) "(#Hctx&#Hinv)".
      iDestruct "Hinv" as (γlock γ1 γ2 γ3) "(#Hlock&#Hinv)".
      iInv "Hinv" as "Hopen" "_".
      destruct_einner "Hopen".
      iApply fupd_mask_weaken; first by solve_ndisj.
      iIntros (?) "Hmem".
      iModIntro. iExists _, _, _. iFrame.
      iPoseProof (@init_mem_split with "Hmem") as "?".
      iFrame.
    }
    { intros. iIntros "H". iDestruct "H" as (ρ) "(#Hctx&#Hinv)".
      iInv "Hinv" as ">Hopen" "_".
      iDestruct "Hopen" as (???) "(?&?&_)".
      iApply fupd_mask_weaken; first by solve_ndisj.
      iIntros (?) "Hmem".
      iModIntro. iExists _, _, _. iFrame.
      iPoseProof (@init_mem_split with "Hmem") as "?".
      iFrame.
    }
    { intros. iIntros "H". iDestruct "H" as "(Hinv&#Hsrc)".
      iDestruct "Hinv" as (invG) "Hinv".
      iDestruct "Hinv" as (???) "(?&?&?)".
      iMod (@inv_alloc myΣ (exm_invG) iN _ CrashInner with "[-]").
      { iNext. iExists _, _, _; iFrame. }
      iModIntro. iFrame. iExists tt, _. iFrame "Hsrc".
    }
    { intros. iIntros "H". iDestruct "H" as "(Hinv&#Hsrc)".
      iDestruct "Hinv" as (invG v) "Hinv".
      iDestruct "Hinv" as "(?&Hinv)".
      iDestruct "Hinv" as (γ1 γ2 γ3) "(Hlock&Hinner)".
      iMod (@lock_init myΣ (ExMachG _ (exm_invG) (exm_mem_inG) (exm_disk_inG)) _ lN
                       lock_addr _ (ExecLockInv γ1 γ2 γ3) with "[$] [-Hinner]") as (γlock) "H".
      { iFrame. }
      iMod (@inv_alloc myΣ (exm_invG) iN _ (ExecInner γ1 γ2 γ3) with "[Hinner]").
      { iFrame. }
      iModIntro. iExists cfg. iFrame "Hsrc". iExists _, _, _, _. iFrame.
    }
    { iIntros (??) "H".
      iDestruct "H" as (?) "(?&H)".
      iDestruct "H" as (????) "(?&Hinv)".
      iInv "Hinv" as "H" "_".
      destruct_einner "H".
      iApply fupd_mask_weaken; first by solve_ndisj.
      iExists _; iFrame.
    }
    { iIntros (??) "H".
      iDestruct "H" as (?) "(?&H)".
      iDestruct "H" as (????) "(Hlock&Hinv)".
      iInv "Hinv" as "H" "_".
      destruct_einner "H".
      iMod (lock_crack with "Hlock") as ">H"; first by solve_ndisj.
      iDestruct "H" as (v) "(?&?)".
      iApply fupd_mask_weaken; first by solve_ndisj.
      iExists _; iFrame.
      iFrame. iIntros (???) "(?&?)".
      iModIntro.
      iExists _. iFrame. iExists _, _, _. iFrame.
      iExists _, _, _. iFrame.
    }
  Qed.

End refinement.