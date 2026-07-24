-- ── Rolle-omlægning: træner ≈ admin (undt. slet-medlem + MobilePay); kaptajn
--    styrer egne holds begivenheder + bøder; bøde-admin fjernes. ──────────────

-- Bøder: staff (admin/træner) eller kaptajn for spillerens hold.
create or replace function public.can_admin_fine(p_target uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select public.is_staff() or exists (
    select 1
    from public.group_members me
    join public.group_members them on them.group_id = me.group_id
    where me.user_id = auth.uid() and me.is_captain
      and them.user_id = p_target
  );
$$;

-- Kan bruger administrere en given træning? (opslag → can_manage_event)
create or replace function public.can_manage_training(p_training_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.trainings t
    where t.id = p_training_id
      and public.can_manage_event(t.created_by, t.group_id, t.group_ids)
  );
$$;

-- Fremmøde for andre: staff/kaptajn/opretter.
alter policy "TP: egen eller admin INSERT" on public.training_participants
  with check (user_id = auth.uid() or public.can_manage_training(training_id));
alter policy "TP: egen eller admin UPDATE" on public.training_participants
  using (user_id = auth.uid() or public.can_manage_training(training_id))
  with check (user_id = auth.uid() or public.can_manage_training(training_id));
alter policy "TP: egen eller admin DELETE" on public.training_participants
  using (user_id = auth.uid() or public.can_manage_training(training_id));

-- Bødetyper: staff.
alter policy "FT: admin opretter"  on public.fine_types with check (public.is_staff());
alter policy "FT: admin opdaterer" on public.fine_types using (public.is_staff()) with check (public.is_staff());
alter policy "FT: admin sletter"   on public.fine_types using (public.is_staff());

-- Hold, medlemskaber, roller: staff. (Slet-medlem forbliver admin via RPC;
-- MobilePay forbliver admin i UI.)
alter policy "groups_admin" on public.groups using (public.is_staff()) with check (public.is_staff());
alter policy "gm_admin" on public.group_members using (public.is_staff()) with check (public.is_staff());
alter policy "Ejer eller admin kan opdatere" on public.profiles
  using (auth.uid() = id or public.is_staff())
  with check (auth.uid() = id or public.is_staff());

-- Poll-options slet: staff (cascade dækker alligevel ved poll-sletning).
alter policy "Options: admin sletter" on public.poll_options using (public.is_staff());

-- Rykker: staff/kaptajn for den træning (var kun admin).
create or replace function public.send_training_reminders(p_training_id uuid)
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare v_count int; v_titel text; v_group_ids uuid[];
begin
  if not public.can_manage_training(p_training_id) then
    raise exception 'Du kan ikke sende rykkere for denne aktivitet' using errcode = '42501';
  end if;
  select titel,
         case when group_ids is not null and array_length(group_ids,1) is not null then group_ids
              when group_id is not null then array[group_id] else null end
    into v_titel, v_group_ids
  from public.trainings where id = p_training_id;
  with non_responders as (
    select p.id from public.profiles p
    where not exists (select 1 from public.training_participants tp
                      where tp.training_id = p_training_id and tp.user_id = p.id)
      and (v_group_ids is null or exists (
        select 1 from public.group_members gm
        where gm.user_id = p.id and gm.group_id = any(v_group_ids)))
  )
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select id, 'training_rykker', 'Rykker: ' || v_titel,
         'Du mangler at svare på tilmelding',
         jsonb_build_object('training_id', p_training_id)
  from non_responders;
  get diagnostics v_count = row_count;
  return v_count;
end $function$;
