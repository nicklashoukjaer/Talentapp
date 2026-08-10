-- ── Push først når begivenheden er synlig — og kun én gang pr. serie ────────
-- Før: triggeren fyrede på HVER indsat række. En serie på 8 gav 8 pushbeskeder
-- med det samme, også når begivenhederne først blev synlige for spillerne en
-- uge før hver. Nu gælder:
--
--   • Er begivenheden ikke synlig endnu (synlig_fra i fremtiden), sendes intet.
--     Cron-jobbet herunder sender den når den bliver synlig.
--   • Oprettes en serie hvor flere bliver synlige samtidig, annonceres serien
--     én gang — ikke én gang pr. begivenhed.
--   • Enkeltstående, straks-synlige begivenheder pusher med det samme som før.
--
-- Afstemninger og bøder rører vi ikke; de bruger fortsat notify_push().

-- ── 1 · Webhook-opsætning ud af koden ───────────────────────────────────────
-- URL og hemmelighed lå hardkodet i migrationsfilerne og dermed i git. De
-- flyttes til en tabel som kun service_role kan læse, og hentes derfra ved
-- kørsel. Værdierne læses ud af den eksisterende notify_push(), så de aldrig
-- skrives ned i en fil.

create schema if not exists private;

create table if not exists private.app_config (
  key   text primary key,
  value text not null
);

alter table private.app_config enable row level security;
revoke all on private.app_config from anon, authenticated;

insert into private.app_config(key, value)
select 'notify_url',
       (regexp_match(pg_get_functiondef(p.oid), $re$fn_url text := '([^']+)'$re$))[1]
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'notify_push'
on conflict (key) do nothing;

insert into private.app_config(key, value)
select 'notify_secret',
       (regexp_match(pg_get_functiondef(p.oid), $re$secret text := '([^']+)'$re$))[1]
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'notify_push'
on conflict (key) do nothing;

-- ── 2 · Hjælper der sender til notify-funktionen ────────────────────────────
create or replace function private.post_notify(p_table text, p_record json)
returns void
language plpgsql
security definer
set search_path = private, public, extensions
as $$
declare
  v_url text;
  v_secret text;
begin
  select value into v_url    from private.app_config where key = 'notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    raise warning 'notify: mangler opsætning i private.app_config';
    return;
  end if;
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type',     'application/json',
                 'x-webhook-secret', v_secret
               ),
    body    := jsonb_build_object(
                 'table',  p_table,
                 'type',   'INSERT',
                 'record', p_record
               ),
    timeout_milliseconds := 5000
  );
end;
$$;

-- ── 3 · push_sent_at på begivenheder ────────────────────────────────────────
alter table public.trainings
  add column if not exists push_sent_at timestamptz;

comment on column public.trainings.push_sent_at is
  'Hvornår der er sendt "ny begivenhed"-push. null = venter på at blive synlig.';

-- VIGTIGT: alt der allerede findes markeres som sendt, så cron-jobbet herunder
-- ikke pludselig annoncerer hele historikken.
update public.trainings set push_sent_at = now() where push_sent_at is null;

-- ── 4 · Trigger: kun synlige, og kun én gang pr. serie ──────────────────────
create or replace function public.notify_training_push()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_series_announced boolean;
begin
  -- Endnu ikke synlig → cron sender den når den bliver det.
  if new.synlig_fra is not null and new.synlig_fra > now() then
    return new;
  end if;

  -- Er et andet medlem af samme serie allerede annonceret? Rækkerne i en
  -- multi-row INSERT behandles én ad gangen, så række 2..n ser række 1.
  v_series_announced := new.series_id is not null and exists (
    select 1 from public.trainings t
     where t.series_id = new.series_id and t.push_sent_at is not null);

  new.push_sent_at := now();
  if v_series_announced then
    return new;
  end if;

  perform private.post_notify('trainings', row_to_json(new));
  return new;
end;
$$;

-- Skal være BEFORE, så push_sent_at kan sættes uden en ekstra UPDATE.
drop trigger if exists trg_notify_trainings on public.trainings;
create trigger trg_notify_trainings
  before insert on public.trainings
  for each row execute function public.notify_training_push();

-- ── 5 · Cron: send når begivenheder bliver synlige ──────────────────────────
create or replace function public.send_due_event_pushes()
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  r record;
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
    perform private.post_notify('trainings', row_to_json(r));
    v_count := v_count + 1;
  end loop;

  -- Marker alle nu-synlige som afsendt — også dem der blev slået sammen med
  -- en serie-annoncering ovenfor.
  update public.trainings
     set push_sent_at = now()
   where push_sent_at is null
     and (synlig_fra is null or synlig_fra <= now())
     and start_tid > now();

  return v_count;
end;
$$;

select cron.schedule(
  'send-due-event-pushes',
  '*/15 * * * *',
  $cron$select public.send_due_event_pushes()$cron$
);
