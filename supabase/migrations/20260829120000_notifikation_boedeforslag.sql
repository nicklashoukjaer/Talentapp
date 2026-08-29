-- ── Besked når nogen foreslår en bødetype ──────────────────────────────────
-- Et forslag landede i admin-sektionen og blev liggende til nogen tilfældigvis
-- kiggede forbi. Nu får de der kan godkende det besked med det samme.
--
-- Modtagere: staff (admin og træner). Det er dem der må aktivere en bødetype,
-- så det er dem der kan gøre noget ved beskeden. Forslagsstilleren får
-- naturligvis ikke besked om sit eget forslag.
--
-- Et forslag kendes på aktiv = false; beløbet er en placeholder indtil admin
-- sætter det rigtige.

create or replace function public.notify_boedeforslag()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $$
declare
  v_af text;
  v_modtagere uuid[];
begin
  if new.aktiv then return new; end if;  -- almindelig bødetype, ikke et forslag

  select navn into v_af from public.profiles where id = auth.uid();

  select array_agg(p.id) into v_modtagere
    from public.profiles p
   where p.rolle in ('admin', 'træner')
     and p.id is distinct from auth.uid();

  if v_modtagere is null then return new; end if;

  insert into public.notifications (recipient_id, kind, titel, body, data)
  select m, 'boedeforslag',
         'Nyt bødeforslag: ' || new.titel,
         coalesce('Foreslået af ' || v_af || '. ', '')
           || 'Godkend eller afvis under Admin → Bøde-opsætning.',
         jsonb_build_object('fine_type_id', new.id)
    from unnest(v_modtagere) as m;

  -- Push med samme besked. Modtagerne sendes med, da det er en navngiven
  -- liste og ikke et hold.
  perform private.post_notify(
    'boedeforslag',
    jsonb_build_object(
      'titel', new.titel,
      '_af', coalesce(v_af, ''),
      '_modtagere', to_jsonb(v_modtagere)
    )::json);
  return new;
end;
$$;

drop trigger if exists trg_notify_boedeforslag on public.fine_types;
create trigger trg_notify_boedeforslag
  after insert on public.fine_types
  for each row execute function public.notify_boedeforslag();
