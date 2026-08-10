-- ── Rykkere springer trænere over ───────────────────────────────────────────
-- En træner for holdet skal ikke rykkes for at tilmelde sig holdets træninger.
-- Er personen træner på ét hold men spiller på et andet, rykkes de fortsat for
-- det hold hvor de er spiller (medlemskabet dér har is_trainer = false).
--
-- Klub-brede begivenheder (uden hold) er uændrede: dér er "træner for holdet"
-- ikke defineret, så alle rykkes som hidtil.
--
-- Begge funktioner er gengivet fra den KØRENDE definition i produktion — den
-- eneste ændring er `and not gm.is_trainer` i medlemskabs-opslaget.

create or replace function public.send_due_reminders()
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  r record;
  v_total int := 0;
  v_groups uuid[];
  v_n int;
begin
  for r in
    select id, titel, tilmeldings_deadline, group_id, group_ids,
      (now() >= tilmeldings_deadline - interval '48 hours' and reminder_48_sent_at is null) as due48,
      (now() >= tilmeldings_deadline - interval '24 hours' and reminder_24_sent_at is null) as due24
    from public.trainings
    where tilmeldings_deadline > now()
      and (
        (now() >= tilmeldings_deadline - interval '48 hours' and reminder_48_sent_at is null)
        or (now() >= tilmeldings_deadline - interval '24 hours' and reminder_24_sent_at is null)
      )
  loop
    v_groups := case
      when r.group_ids is not null and array_length(r.group_ids, 1) is not null then r.group_ids
      when r.group_id is not null then array[r.group_id]
      else null end;

    with non_responders as (
      select p.id from public.profiles p
      where not exists (
        select 1 from public.training_participants tp
        where tp.training_id = r.id and tp.user_id = p.id
      )
      and (
        v_groups is null
        or exists (
          select 1 from public.group_members gm
          where gm.user_id = p.id and gm.group_id = any(v_groups)
            and not gm.is_trainer
        )
      )
    )
    insert into public.notifications(recipient_id, kind, titel, body, data)
    select id, 'training_rykker',
      'Rykker: ' || r.titel,
      case when r.due24 then 'Sidste chance — tilmelding lukker snart'
           else 'Du mangler at svare på tilmelding' end,
      jsonb_build_object('training_id', r.id,
        'reminder', case when r.due24 then '24h' else '48h' end)
    from non_responders;
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;

    if r.due24 then
      update public.trainings
        set reminder_24_sent_at = now(),
            reminder_48_sent_at = coalesce(reminder_48_sent_at, now())
        where id = r.id;
    elsif r.due48 then
      update public.trainings set reminder_48_sent_at = now() where id = r.id;
    end if;
  end loop;
  return v_total;
end $function$;

create or replace function public.send_training_reminders(
    p_training_id uuid, p_exclude uuid[] default '{}'::uuid[])
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
      and not (p.id = any(coalesce(p_exclude, '{}'::uuid[])))
      and (v_group_ids is null or exists (
        select 1 from public.group_members gm
        where gm.user_id = p.id and gm.group_id = any(v_group_ids)
          and not gm.is_trainer))
  )
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select id, 'training_rykker', 'Rykker: ' || v_titel,
         'Du mangler at svare på tilmelding',
         jsonb_build_object('training_id', p_training_id)
  from non_responders;
  get diagnostics v_count = row_count;
  return v_count;
end $function$;
