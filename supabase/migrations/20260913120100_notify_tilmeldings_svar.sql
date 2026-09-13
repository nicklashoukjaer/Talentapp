-- ── Besked ved til- og afmelding ───────────────────────────────────────────
-- Én besked pr. svar, til abonnenterne på begivenhedens hold.
--
-- Tre ting sendes der bevidst IKKE på:
--   • Systemkald (cron, deadline-jobbet) — auth.uid() er null.
--   • Svar der ikke ændrer noget — samme status igen.
--   • Den der trykkede, og personen det handler om — de ved det godt.

create or replace function public.notify_tilmeldings_svar()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $$
declare
  v_groups     uuid[];
  v_titel      text;
  v_start      timestamptz;
  v_navn       text;
  v_hvad       text;
  v_ikon       text;
  v_modtagere  uuid[];
begin
  if auth.uid() is null then return new; end if;

  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  select t.titel, t.start_tid,
         case
           when t.group_ids is not null
                and array_length(t.group_ids, 1) is not null then t.group_ids
           when t.group_id is not null then array[t.group_id]
           else null
         end
    into v_titel, v_start, v_groups
    from public.trainings t
   where t.id = new.training_id;

  -- Klub-brede begivenheder hører ikke til et hold og har derfor ingen
  -- abonnenter. Ingen besked.
  if v_groups is null then return new; end if;

  select array_agg(distinct a.user_id) into v_modtagere
    from public.tilmeldings_abonnenter a
   where a.group_id = any(v_groups)
     and a.user_id is distinct from auth.uid()
     and a.user_id is distinct from new.user_id;

  if v_modtagere is null then return new; end if;

  select navn into v_navn from public.profiles where id = new.user_id;

  v_hvad := case new.status
              when 'afmeldt'    then 'har meldt afbud'
              when 'venteliste' then 'står på venteliste'
              else                   'har tilmeldt sig'
            end;
  v_ikon := case when new.status = 'afmeldt' then '❌' else '✅' end;

  insert into public.notifications (recipient_id, kind, titel, body, data)
  select m,
         'training_svar',
         coalesce(v_navn, 'En spiller') || ' ' || v_hvad,
         coalesce(v_titel, 'Begivenhed') || ' · '
           || to_char(v_start at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI'),
         jsonb_build_object('training_id', new.training_id)
    from unnest(v_modtagere) as m;

  -- Push. Navngiven modtagerliste, ikke et hold — derfor _modtagere.
  perform private.post_notify(
    'training_svar',
    jsonb_build_object(
      'titel',      coalesce(v_titel, 'Begivenhed'),
      'start_tid',  v_start,
      '_navn',      coalesce(v_navn, 'En spiller'),
      '_hvad',      v_hvad,
      '_ikon',      v_ikon,
      '_modtagere', to_jsonb(v_modtagere)
    )::json);

  return new;
end;
$$;

drop trigger if exists trg_notify_tilmeldings_svar on public.training_participants;
create trigger trg_notify_tilmeldings_svar
  after insert or update on public.training_participants
  for each row execute function public.notify_tilmeldings_svar();
