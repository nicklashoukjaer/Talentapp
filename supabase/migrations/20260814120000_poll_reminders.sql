-- ── Rykkere på afstemninger ─────────────────────────────────────────────────
-- Begivenheder har haft "påmind alle der mangler" længe; afstemninger havde
-- ikke noget tilsvarende, selvom notif_kind allerede havde værdien
-- 'poll_rykker' liggende ubrugt.
--
-- Bygget som en tro kopi af send_training_reminders, med samme p_exclude så
-- man kan fravælge enkeltpersoner inden man sender.
--
-- Rettighed genbruger can_manage_event(): admin, træner, afstemningens
-- opretter, eller kaptajn for et af dens hold. Tjekket ligger i databasen, så
-- det ikke kun hviler på at UI'et skjuler knappen.

create or replace function public.send_poll_reminders(
    p_poll_id uuid, p_exclude uuid[] default '{}'::uuid[])
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_count int;
  v_titel text;
  v_created_by uuid;
  v_group_id uuid;
  v_groups uuid[];
begin
  select titel, created_by, group_id,
         case when group_ids is not null and array_length(group_ids, 1) is not null
                then group_ids
              when group_id is not null then array[group_id]
              else null end
    into v_titel, v_created_by, v_group_id, v_groups
  from public.polls where id = p_poll_id;

  if v_titel is null then
    raise exception 'Afstemningen findes ikke' using errcode = '42704';
  end if;

  if not public.can_manage_event(v_created_by, v_group_id, v_groups) then
    raise exception 'Du kan ikke sende rykkere for denne afstemning'
      using errcode = '42501';
  end if;

  -- Mangler at stemme: ingen svar på nogen af afstemningens muligheder.
  -- Trænere for holdet er ikke stemme-pligtige. Klub-brede afstemninger
  -- (uden hold) rammer alle, som rykkere på begivenheder også gør.
  with non_responders as (
    select p.id from public.profiles p
    where not exists (
        select 1 from public.poll_responses r
        join public.poll_options o on o.id = r.poll_option_id
        where o.poll_id = p_poll_id and r.user_id = p.id)
      and not (p.id = any(coalesce(p_exclude, '{}'::uuid[])))
      and (v_groups is null or exists (
        select 1 from public.group_members gm
        where gm.user_id = p.id and gm.group_id = any(v_groups)
          and not gm.is_trainer))
  )
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select id, 'poll_rykker', 'Rykker: ' || v_titel,
         'Du mangler at stemme',
         jsonb_build_object('poll_id', p_poll_id)
  from non_responders;
  get diagnostics v_count = row_count;
  return v_count;
end $function$;
