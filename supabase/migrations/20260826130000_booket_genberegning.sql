-- ── Booket-markeringen følger nu kampene, også når de forsvinder ────────────
-- Første udgave satte kun markeringen. Slettede man kampen igen — eller
-- flyttede den til en anden dato — blev markeringen stående, og man skulle
-- selv holde øje med hvilke datoer der ikke længere var booket.
--
-- Nu genberegnes datoen i stedet: en dato er booket hvis der FINDES en kamp
-- på den for et af afstemningens hold. Ved sletning og flytning genberegnes
-- både den gamle og den nye dato.
--
-- Bemærk: markerer man en dato i hånden og der senere oprettes og slettes en
-- kamp samme dag, forsvinder den manuelle markering med. Det er prisen for at
-- markeringen kan passe sig selv, og den kan sættes igen med ét tryk.

create or replace function public.genberegn_booket(p_dato date, p_groups uuid[])
returns void
language sql
security definer
set search_path to 'public'
as $$
  update public.poll_options o
     set booket = exists (
       select 1 from public.trainings t
        where lower(t.titel) like '%kamp%'
          and (t.start_tid at time zone 'Europe/Copenhagen')::date = p_dato
          and (p_groups is null
               or coalesce(t.group_ids, array[t.group_id]) && p_groups)
     )
    from public.polls p
   where o.poll_id = p.id
     and (o.option_tid at time zone 'Europe/Copenhagen')::date = p_dato
     and (p_groups is null
          or coalesce(p.group_ids, array[p.group_id]) && p_groups);
$$;

create or replace function public.marker_booket_kampdato()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ny_dato date; v_gl_dato date;
  v_ny_groups uuid[]; v_gl_groups uuid[];
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_gl_dato := (old.start_tid at time zone 'Europe/Copenhagen')::date;
    v_gl_groups := case
      when old.group_ids is not null and array_length(old.group_ids, 1) is not null
        then old.group_ids
      when old.group_id is not null then array[old.group_id]
      else null end;
    perform public.genberegn_booket(v_gl_dato, v_gl_groups);
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    v_ny_dato := (new.start_tid at time zone 'Europe/Copenhagen')::date;
    v_ny_groups := case
      when new.group_ids is not null and array_length(new.group_ids, 1) is not null
        then new.group_ids
      when new.group_id is not null then array[new.group_id]
      else null end;
    perform public.genberegn_booket(v_ny_dato, v_ny_groups);
  end if;

  return null; -- AFTER-trigger; returværdien bruges ikke
end;
$$;

drop trigger if exists trg_marker_booket_kampdato on public.trainings;
create trigger trg_marker_booket_kampdato
  after insert or delete or update of start_tid, titel, group_id, group_ids
  on public.trainings
  for each row execute function public.marker_booket_kampdato();
