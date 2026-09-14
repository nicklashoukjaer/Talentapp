-- ── Besked når nogen skriver en kommentar på en begivenhed ─────────────────
-- Modtagere: dem der kan gøre noget ved det.
--   • admins — klub-bredt, de skal kunne følge med i alt
--   • trænere og kaptajner PÅ BEGIVENHEDENS HOLD
--
-- Bevidst ikke is_staff(): den er rolle-baseret og dermed klub-bred, så en
-- træner for Talentløse 1 ville få kommentarer fra Damerne. Trænere tildeles
-- pr. hold via group_members.is_trainer, og det respekteres her.
--
-- Skribenten får aldrig besked om sin egen kommentar.

create or replace function public.notify_training_kommentar()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $$
declare
  v_groups    uuid[];
  v_titel     text;
  v_start     timestamptz;
  v_navn      text;
  v_uddrag    text;
  v_modtagere uuid[];
begin
  select t.titel, t.start_tid,
         case
           when t.group_ids is not null
                and array_length(t.group_ids, 1) is not null then t.group_ids
           when t.group_id is not null then array[t.group_id]
           else '{}'::uuid[]
         end
    into v_titel, v_start, v_groups
    from public.trainings t
   where t.id = new.training_id;

  select array_agg(distinct id) into v_modtagere from (
    -- Admins: klub-bredt
    select p.id from public.profiles p where p.rolle = 'admin'
    union
    -- Trænere og kaptajner på begivenhedens hold
    select gm.user_id from public.group_members gm
     where (gm.is_trainer or gm.is_captain)
       and gm.group_id = any(v_groups)
  ) som_kan_handle
   where id is distinct from new.user_id;

  if v_modtagere is null then return new; end if;

  select navn into v_navn from public.profiles where id = new.user_id;

  -- Kort uddrag; hele kommentaren står inde i begivenheden.
  v_uddrag := case
    when length(new.body) > 90 then left(new.body, 90) || '…'
    else new.body
  end;

  insert into public.notifications (recipient_id, kind, titel, body, data)
  select m,
         'training_kommentar',
         coalesce(v_navn, 'En spiller') || ' skrev på '
           || coalesce(v_titel, 'en begivenhed'),
         v_uddrag,
         jsonb_build_object('training_id', new.training_id)
    from unnest(v_modtagere) as m;

  perform private.post_notify(
    'training_kommentar',
    jsonb_build_object(
      'titel',      coalesce(v_titel, 'Begivenhed'),
      'start_tid',  v_start,
      '_navn',      coalesce(v_navn, 'En spiller'),
      '_uddrag',    v_uddrag,
      '_modtagere', to_jsonb(v_modtagere)
    )::json);

  return new;
end;
$$;

drop trigger if exists trg_notify_training_kommentar on public.training_comments;
create trigger trg_notify_training_kommentar
  after insert on public.training_comments
  for each row execute function public.notify_training_kommentar();
