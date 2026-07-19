alter table public.trainings
  add column if not exists reminder_48_sent_at timestamptz,
  add column if not exists reminder_24_sent_at timestamptz;

create or replace function public.send_due_reminders()
returns integer
language plpgsql security definer set search_path to 'public' as $$
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
end $$;

-- Planlæg jobbet hvert 15. minut (afmeld først hvis det allerede findes).
select cron.unschedule('send-due-reminders')
  where exists (select 1 from cron.job where jobname = 'send-due-reminders');
select cron.schedule('send-due-reminders', '*/15 * * * *', $job$select public.send_due_reminders()$job$);
