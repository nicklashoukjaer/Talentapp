-- ── Besked når en begivenhed ændres ─────────────────────────────────────────
-- Flyttes en træning eller skifter en kamp hal, opdagede man det kun ved at
-- åbne appen og selv lægge mærke til det.
--
-- Beskeden fortæller HVAD der er ændret — "Tid: 18:00 → 19:00" siger noget,
-- "der er sket en ændring" gør ikke.
--
-- Udløses kun af felter brugerne kan se. Cron'ens interne opdateringer
-- (reminder_*_sent_at, push_sent_at) og synlig_fra rører den ikke: "Udgiv nu"
-- sender allerede sin egen besked, og ellers ville man få to.
--
-- Modtagere: holdets medlemmer plus alle der selv er sat på begivenheden
-- (fx en afløser fra et andet hold). Den der laver ændringen får ikke besked
-- om sin egen handling.

create or replace function public.notify_training_changed()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_groups uuid[];
  v_dele text[] := '{}';
  v_body text;
begin
  -- Hvad er der ændret? Kun ting man kan se i appen.
  if new.titel is distinct from old.titel then
    v_dele := v_dele || ('Titel: ' || old.titel || ' → ' || new.titel);
  end if;
  if new.start_tid is distinct from old.start_tid then
    v_dele := v_dele || (
      'Tid: ' || to_char(old.start_tid at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI')
      || ' → ' || to_char(new.start_tid at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI'));
  elsif new.slut_tid is distinct from old.slut_tid then
    v_dele := v_dele || (
      'Slutter nu ' || to_char(new.slut_tid at time zone 'Europe/Copenhagen', 'HH24:MI'));
  end if;
  if new.adresse is distinct from old.adresse then
    v_dele := v_dele || ('Sted: ' || coalesce(new.adresse, 'ikke angivet'));
  end if;
  if new.tilmeldings_deadline is distinct from old.tilmeldings_deadline then
    v_dele := v_dele || (
      'Tilmeldingsfrist: '
      || to_char(new.tilmeldings_deadline at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI'));
  end if;
  if new.max_deltagere is distinct from old.max_deltagere then
    v_dele := v_dele || ('Pladser: ' || coalesce(new.max_deltagere::text, 'ubegrænset'));
  end if;
  if coalesce(new.group_ids, array[new.group_id]) is distinct from
     coalesce(old.group_ids, array[old.group_id]) then
    v_dele := v_dele || 'Holdene er ændret';
  end if;

  if array_length(v_dele, 1) is null then
    return new; -- intet synligt ændret
  end if;

  v_body := array_to_string(v_dele, ' · ');

  v_groups := case
    when new.group_ids is not null and array_length(new.group_ids, 1) is not null
      then new.group_ids
    when new.group_id is not null then array[new.group_id]
    else null end;

  insert into public.notifications (recipient_id, kind, titel, body, data)
  select p.id, 'training_aendret', 'Ændret: ' || new.titel, v_body,
         jsonb_build_object('training_id', new.id)
    from public.profiles p
   where p.id is distinct from auth.uid()          -- ikke til den der ændrede
     and (
       v_groups is null
       or exists (select 1 from public.group_members gm
                   where gm.user_id = p.id and gm.group_id = any(v_groups))
       -- Afløsere m.fl. der er sat på uden at være på holdet.
       or exists (select 1 from public.training_participants tp
                   where tp.training_id = new.id and tp.user_id = p.id)
     );
  return new;
end;
$$;

drop trigger if exists trg_notify_training_changed on public.trainings;
create trigger trg_notify_training_changed
  after update of titel, start_tid, slut_tid, adresse,
                  tilmeldings_deadline, max_deltagere, group_id, group_ids
  on public.trainings
  for each row execute function public.notify_training_changed();
