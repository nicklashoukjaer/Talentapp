-- ─────────────────────────────────────────────────────────────────────────────
-- Push-notifikationer: kald Edge Function 'notify' når der oprettes en ny
-- træning/kamp, afstemning eller bøde. Bruger pg_net til at lave et HTTP-kald
-- fra databasen.
--
-- Secret + funktions-URL er allerede udfyldt til jeres projekt. Den SAMME
-- secret skal sættes som Edge Function-secret NOTIFY_WEBHOOK_SECRET.
-- ─────────────────────────────────────────────────────────────────────────────

create extension if not exists pg_net;

create or replace function public.notify_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  fn_url text := 'https://uaydipzotooxqisodshw.supabase.co/functions/v1/notify';
  secret text := 'R8yRTLQrfEkcfZw1oFYlf6c8UaYnWPWC';
begin
  perform net.http_post(
    url     := fn_url,
    headers := jsonb_build_object(
                 'Content-Type',     'application/json',
                 'x-webhook-secret', secret
               ),
    body    := jsonb_build_object(
                 'table',  tg_table_name,
                 'type',   tg_op,
                 'record', row_to_json(new)
               ),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_trainings on public.trainings;
create trigger trg_notify_trainings
  after insert on public.trainings
  for each row execute function public.notify_push();

drop trigger if exists trg_notify_polls on public.polls;
create trigger trg_notify_polls
  after insert on public.polls
  for each row execute function public.notify_push();

drop trigger if exists trg_notify_fines on public.fines;
create trigger trg_notify_fines
  after insert on public.fines
  for each row execute function public.notify_push();
