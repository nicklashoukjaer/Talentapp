-- Må den aktuelle bruger redigere/slette en begivenhed/afstemning?
--   • staff (admin/træner): altid
--   • den der oprettede den
--   • en kaptajn for et af begivenhedens hold
create or replace function public.can_manage_event(
  p_created_by uuid, p_group_id uuid, p_group_ids uuid[] default null)
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select public.is_staff()
    or p_created_by = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.user_id = auth.uid() and gm.is_captain
        and (gm.group_id = any(coalesce(p_group_ids, '{}'::uuid[]))
             or gm.group_id = p_group_id)
    );
$$;

alter policy "Trainings: admin opdaterer" on public.trainings
  using (public.can_manage_event(created_by, group_id, group_ids))
  with check (public.can_manage_event(created_by, group_id, group_ids));
alter policy "Trainings: admin sletter" on public.trainings
  using (public.can_manage_event(created_by, group_id, group_ids));

alter policy "Polls: admin opdaterer" on public.polls
  using (public.can_manage_event(created_by, group_id, null))
  with check (public.can_manage_event(created_by, group_id, null));
alter policy "Polls: admin sletter" on public.polls
  using (public.can_manage_event(created_by, group_id, null));
