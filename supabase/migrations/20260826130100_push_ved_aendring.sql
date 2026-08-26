-- ── Ændringer skal også give push, ikke kun klokke ─────────────────────────
-- En flyttet kamp er præcis den slags man skal vide med det samme, og ikke
-- først næste gang man tilfældigvis åbner appen.
--
-- Klokke-beskeden bevares uændret; her lægges push oveni. Payloaden får to
-- ekstra felter som edge-funktionen bruger: _aendringer (teksten) og _af
-- (den der ændrede, så de ikke får push om deres egen handling).

create or replace function public.notify_training_changed()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $$
declare
  v_groups uuid[];
  v_dele text[] := '{}';
  v_body text;
begin
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
    return new;
  end if;

  v_body := array_to_string(v_dele, ' · ');

  v_groups := case
    when new.group_ids is not null and array_length(new.group_ids, 1) is not null
      then new.group_ids
    when new.group_id is not null then array[new.group_id]
    else null end;

  -- Klokken (uændret)
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select p.id, 'training_aendret', 'Ændret: ' || new.titel, v_body,
         jsonb_build_object('training_id', new.id)
    from public.profiles p
   where p.id is distinct from auth.uid()
     and (
       v_groups is null
       or exists (select 1 from public.group_members gm
                   where gm.user_id = p.id and gm.group_id = any(v_groups))
       or exists (select 1 from public.training_participants tp
                   where tp.training_id = new.id and tp.user_id = p.id)
     );

  -- Push
  perform private.post_notify(
    'trainings_aendret',
    (to_jsonb(new)
      || jsonb_build_object('_aendringer', v_body, '_af', auth.uid()))::json);
  return new;
end;
$$;
