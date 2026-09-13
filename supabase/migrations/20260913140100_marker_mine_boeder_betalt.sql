-- TRIN 3 ── Spilleren melder sine egne bøder betalt ────────────────────────
-- RLS på fines kræver can_admin_fine() for at opdatere, og den regel bliver
-- stående. Denne funktion er den eneste undtagelse, og den er snæver:
-- den rører KUN kalderens egne ubetalte bøder.
--
-- Kreditter ("stikker", negative beløb) afregnes med, præcis som admins
-- "Gør op" gør det. Ellers ville en oversprunget kredit blive ved med at give
-- rabat næste gang.

create or replace function public.marker_mine_boeder_betalt()
returns table (antal int, belob_oere bigint)
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $$
declare
  v_uid   uuid := auth.uid();
  v_antal int;
  v_sum   bigint;
  v_navn  text;
  v_modtagere uuid[];
begin
  if v_uid is null then
    raise exception 'Du skal være logget ind' using errcode = '42501';
  end if;

  with opdaterede as (
    update public.fines f
       set status      = 'godkendt_betalt',
           paid_at     = now(),
           approved_by = v_uid,
           selvmeldt   = true
     where f.user_id = v_uid
       and f.status  = 'ubetalt'
    -- Alias: returkolonnen hedder også belob_oere, og uden det er
    -- henvisningen tvetydig for PL/pgSQL.
    returning f.belob_oere as oere
  )
  select count(*)::int, coalesce(sum(oere), 0)::bigint
    into v_antal, v_sum
    from opdaterede;

  if v_antal = 0 then
    return query select 0, 0::bigint;
    return;
  end if;

  select navn into v_navn from public.profiles where id = v_uid;

  -- Besked til dem der kan gøre noget ved det, så betalingen kan tjekkes i
  -- MobilePay mens den er frisk.
  select array_agg(p.id) into v_modtagere
    from public.profiles p
   where p.rolle in ('admin', 'træner')
     and p.id is distinct from v_uid;

  if v_modtagere is not null then
    insert into public.notifications (recipient_id, kind, titel, body, data)
    select m,
           'boede_selvmeldt',
           coalesce(v_navn, 'En spiller') || ' har meldt betalt',
           v_antal || ' bøde' || case when v_antal = 1 then '' else 'r' end
             || ' · ' || to_char(v_sum / 100.0, 'FM999G999D00') || ' kr'
             || ' — tjek MobilePay',
           jsonb_build_object('user_id', v_uid)
      from unnest(v_modtagere) as m;

    perform private.post_notify(
      'boede_selvmeldt',
      jsonb_build_object(
        '_navn',      coalesce(v_navn, 'En spiller'),
        '_antal',     v_antal,
        '_belob',     v_sum,
        '_modtagere', to_jsonb(v_modtagere)
      )::json);
  end if;

  return query select v_antal, v_sum;
end;
$$;

revoke all on function public.marker_mine_boeder_betalt() from public;
grant execute on function public.marker_mine_boeder_betalt() to authenticated;
