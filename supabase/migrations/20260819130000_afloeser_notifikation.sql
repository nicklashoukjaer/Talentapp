-- ── Besked når man bliver sat på af en anden ────────────────────────────────
-- Staff og kaptajner kan tilmelde andre — fx en afløser fra et andet hold.
-- Uden en besked opdager personen det først næste gang de tilfældigvis åbner
-- appen, og det er for sent hvis kampen er i morgen.
--
-- Enum-værdien 'training_tilmeldt_af_anden' er tilføjet i en separat kørsel;
-- Postgres tillader ikke at bruge en ny enum-værdi i samme transaktion som
-- den oprettes.
--
-- Melder man sig selv, sendes intet — man ved jo godt hvad man har trykket.

create or replace function public.notify_added_to_training()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_titel text; v_start timestamptz; v_adresse text; v_af text;
begin
  if new.status <> 'tilmeldt' then return new; end if;
  -- Selvtilmelding, cron og andre system-kald skal ikke give besked.
  if auth.uid() is null or new.user_id = auth.uid() then return new; end if;
  -- Var man allerede tilmeldt, er der ikke sket noget nyt.
  if tg_op = 'UPDATE' and old.status = 'tilmeldt' then return new; end if;

  select titel, start_tid, adresse
    into v_titel, v_start, v_adresse
    from public.trainings where id = new.training_id;
  select navn into v_af from public.profiles where id = auth.uid();

  insert into public.notifications (recipient_id, kind, titel, body, data)
  values (
    new.user_id,
    'training_tilmeldt_af_anden',
    'Du er sat på: ' || coalesce(v_titel, 'en begivenhed'),
    to_char(v_start at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI')
      || ' – ' || coalesce(v_adresse, '')
      || coalesce(' · tilføjet af ' || v_af, ''),
    jsonb_build_object('training_id', new.training_id));
  return new;
end;
$$;

drop trigger if exists trg_notify_added_to_training on public.training_participants;
create trigger trg_notify_added_to_training
  after insert or update on public.training_participants
  for each row execute function public.notify_added_to_training();
