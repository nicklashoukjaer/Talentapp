-- ── Marker afstemningens dato som booket når kampen planlægges ──────────────
-- Man stemte om kampdatoer, bookede kampen, og skulle så huske at gå tilbage
-- og sætte markeringen i hånden. Nu sker det af sig selv.
--
-- Regler:
--   • Kun begivenheder der er KAMPE — samme regel som appens egen inddeling:
--     titlen indeholder "kamp" (dækker hjemmekamp og udekamp).
--   • Kun afstemninger der deler mindst ét hold med kampen. En T1-kamp må ikke
--     markere Damernes afstemning.
--   • Datoen sammenlignes på DAGEN i dansk tid, så heldags-muligheder (00:00)
--     også rammes af en kamp kl. 11.
--   • Uanset om afstemningen er lukket — man booker jo netop EFTER at have
--     stemt.
--
-- Triggeren SÆTTER kun markeringen, den fjerner den aldrig. Ellers ville
-- automatikken kunne overskrive noget en træner selv har markeret eller
-- fjernet. Aflyses en kamp, fjernes markeringen med knappen i afstemningen.

create or replace function public.marker_booket_kampdato()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_groups uuid[];
  v_dato date;
begin
  if new.titel is null or position('kamp' in lower(new.titel)) = 0 then
    return new;
  end if;

  v_groups := case
    when new.group_ids is not null and array_length(new.group_ids, 1) is not null
      then new.group_ids
    when new.group_id is not null then array[new.group_id]
    else null end;
  v_dato := (new.start_tid at time zone 'Europe/Copenhagen')::date;

  update public.poll_options o
     set booket = true
    from public.polls p
   where o.poll_id = p.id
     and not o.booket
     and (o.option_tid at time zone 'Europe/Copenhagen')::date = v_dato
     and (
       -- Klub-bred kamp rammer alle afstemninger; ellers skal holdene overlappe.
       v_groups is null
       or coalesce(p.group_ids, array[p.group_id]) && v_groups
     );
  return new;
end;
$$;

drop trigger if exists trg_marker_booket_kampdato on public.trainings;
create trigger trg_marker_booket_kampdato
  after insert or update of start_tid, titel, group_id, group_ids
  on public.trainings
  for each row execute function public.marker_booket_kampdato();

-- ── Efterfyld: kampe der allerede var planlagt da triggeren blev lavet ──────
-- Triggeren virker kun fremadrettet, og der lå 12 kampe på afstemnings-datoer
-- hvoraf 6 ikke var markeret. Samme regel som ovenfor, kørt én gang.
update public.poll_options o
   set booket = true
  from public.polls p, public.trainings t
 where o.poll_id = p.id
   and not o.booket
   and lower(t.titel) like '%kamp%'
   and (o.option_tid at time zone 'Europe/Copenhagen')::date
     = (t.start_tid at time zone 'Europe/Copenhagen')::date
   and coalesce(p.group_ids, array[p.group_id])
     && coalesce(t.group_ids, array[t.group_id]);
