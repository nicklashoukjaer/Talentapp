-- ── In-app klokken følger samme regler som push ─────────────────────────────
-- Der lå en anden trigger på trainings, `trg_notify_new_training`, som indsatte
-- en notifikation til HVER profil i klubben (`from public.profiles p`) — uden
-- hold-filter, uden synlighedstjek og uden serie-sammenlægning. Det er derfor
-- man kunne få klokke-besked om et andet holds træning og så ikke kunne finde
-- den i Oversigten.
--
-- De to kanaler (push + klokke) skal annoncere det samme til de samme folk på
-- samme tidspunkt, så de samles i én funktion og ét trigger-kald.

-- ── 1 · Fælles annoncering: push + klokke ───────────────────────────────────
create or replace function private.announce_training(t public.trainings)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_groups uuid[];
begin
  perform private.post_notify('trainings', row_to_json(t));

  v_groups := case
    when t.group_ids is not null and array_length(t.group_ids, 1) is not null
      then t.group_ids
    when t.group_id is not null then array[t.group_id]
    else null end;

  -- Holdets medlemmer (trænere inkl. — de er på holdet) plus alle admins.
  -- Klub-brede begivenheder uden hold går fortsat til alle.
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select p.id,
         'training_oprettet',
         'Ny træning: ' || t.titel,
         to_char(t.start_tid at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI')
           || ' – ' || t.adresse,
         jsonb_build_object('training_id', t.id)
    from public.profiles p
   where v_groups is null
      or p.rolle = 'admin'
      or exists (
           select 1 from public.group_members gm
            where gm.user_id = p.id and gm.group_id = any(v_groups));
end;
$$;

-- ── 2 · Trigger og cron annoncerer nu begge kanaler ─────────────────────────
create or replace function public.notify_training_push()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_series_announced boolean;
begin
  if new.synlig_fra is not null and new.synlig_fra > now() then
    return new;
  end if;

  v_series_announced := new.series_id is not null and exists (
    select 1 from public.trainings t
     where t.series_id = new.series_id and t.push_sent_at is not null);

  new.push_sent_at := now();
  if v_series_announced then
    return new;
  end if;

  perform private.announce_training(new);
  return new;
end;
$$;

create or replace function public.send_due_event_pushes()
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  r public.trainings%rowtype;
  v_count int := 0;
begin
  for r in
    select distinct on (coalesce(t.series_id::text, t.id::text)) t.*
      from public.trainings t
     where t.push_sent_at is null
       and (t.synlig_fra is null or t.synlig_fra <= now())
       and t.start_tid > now()
     order by coalesce(t.series_id::text, t.id::text), t.start_tid
  loop
    perform private.announce_training(r);
    v_count := v_count + 1;
  end loop;

  update public.trainings
     set push_sent_at = now()
   where push_sent_at is null
     and (synlig_fra is null or synlig_fra <= now())
     and start_tid > now();

  return v_count;
end;
$$;

-- ── 3 · Den gamle "til alle"-trigger går ud ─────────────────────────────────
-- Erstattet af announce_training() ovenfor, der kaldes ét sted fra.
drop trigger if exists trg_notify_new_training on public.trainings;
drop function if exists public.notify_new_training();
