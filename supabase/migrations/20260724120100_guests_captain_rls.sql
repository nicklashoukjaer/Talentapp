alter policy "tg_insert" on public.training_guests
  with check ((public.is_staff() or public.can_manage_training(training_id)) and added_by = auth.uid());
alter policy "tg_delete" on public.training_guests
  using (public.is_staff() or public.can_manage_training(training_id));
