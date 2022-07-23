From Perennial.program_proof Require Export grove_prelude.
(* TODO: minimize dependency. *)

Lemma list_delete_insert_delete {A} (l : list A) i v :
  (i < length l)%nat ->
  delete i (<[i := v]> l) = delete i l.
Proof.
  intros.
  rewrite insert_take_drop; last done.
  rewrite delete_take_drop.
  replace i with (length (take i l)) at 1; last first.
  { apply take_length_le. lia. }
  rewrite take_app.
  rewrite cons_middle.
  replace (S i) with (length (take i l ++ [v])); last first.
  { rewrite app_length.
    simpl.
    rewrite take_length_le; last lia.
    lia.
  }
  rewrite app_assoc.
  rewrite drop_app.
  rewrite app_length.
  simpl.
  rewrite take_length_le; last lia.
  replace (i + 1)%nat with (S i)%nat by lia.
  by rewrite -delete_take_drop.
Qed.
  
Lemma list_to_map_insert {A} `{FinMap K M} (l : list (K * A)) k v v' i :
  NoDup l.*1 ->
  l !! i = Some (k, v) ->
  <[k := v']> (list_to_map l) =@{M A} list_to_map (<[i := (k, v')]> l).
Proof.
  intros.
  apply lookup_lt_Some in H8 as Hlength.
  apply delete_Permutation in H8 as Hperm.
  apply Permutation_sym in Hperm.
  rewrite -(list_to_map_proper ((k, v) :: (delete i l)) l); last done; last first.
  { apply NoDup_Permutation_proper with l.*1; [by apply fmap_Permutation | done]. }
  set l' := <[_:=_]> l.
  assert (Hlookup : l' !! i = Some (k, v')).
  { rewrite list_lookup_insert; auto. }
  apply delete_Permutation in Hlookup as Hperm'.
  apply Permutation_sym in Hperm'.
  rewrite -(list_to_map_proper ((k, v') :: (delete i l')) l'); last done; last first.
  { apply NoDup_Permutation_proper with l'.*1; first by apply fmap_Permutation.
    rewrite list_fmap_insert.
    simpl.
    rewrite list_insert_id; first done.
    rewrite list_lookup_fmap.
    by rewrite H8.
  }
  do 2 rewrite list_to_map_cons.
  rewrite insert_insert.
  by rewrite list_delete_insert_delete.
Qed.

Lemma list_swap_with_end {A} (l : list A) (i : nat) (xlast xi : A) :
  (i < pred (length l))%nat ->
  last l = Some xlast ->
  l !! i = Some xi ->
  <[i := xlast]> (removelast l) ≡ₚ delete i l.
Proof.
  intros Hlt Hlast Hi.
  apply last_Some in Hlast as [l' El].
  rewrite El.
  assert (Hlen : length l' = pred (length l)).
  { rewrite El. rewrite last_length. lia. }
  (* RHS *)
  rewrite delete_take_drop.
  rewrite take_app_le; last lia.
  rewrite drop_app_le; last lia.
  (* LHS *)
  rewrite removelast_last.
  rewrite insert_take_drop; last lia.
  apply Permutation_app_head.
  apply Permutation_cons_append.
Qed.

Lemma list_insert_at_end {A} (l : list A) (x : A) :
  l ≠ [] ->
  <[pred (length l) := x]> l = (removelast l) ++ [x].
Proof.
  intros Hnotnil.
  destruct (@nil_or_length_pos A l); first contradiction.
  rewrite insert_take_drop; last lia.
  rewrite -removelast_firstn_len.
  replace (S _) with (length l); last lia.
  by rewrite drop_all.
Qed.
