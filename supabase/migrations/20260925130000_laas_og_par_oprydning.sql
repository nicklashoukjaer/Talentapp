-- ── Lås på tavlen + oprydning i par-historikken ───────────────────────────

-- Låsen gemmes, så den overlever at træneren lukker og åbner tavlen igen
-- midt i en træning.
alter table public.training_round_slots
  add column if not exists laast boolean not null default false;

comment on column public.training_round_slots.laast is
  'Spilleren bliver stående når resten blandes.';

-- ── Oprydning: fjern et pars historik og stjerne ──────────────────────────
-- Til oprydning efter test. Den fjerner BÅDE stjernen OG de to spillere fra
-- de runder hvor de stod sammen — de runder bliver dermed ufuldstændige.
-- Derfor returneres hvad der blev rørt, så appen kan fortælle præcist hvad
-- der skete.
create or replace function public.slet_par_historik(p_a uuid, p_b uuid)
returns table (runder_ryddet int, kemi_fjernet int)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lav  uuid := least(p_a, p_b);
  v_hoej uuid := greatest(p_a, p_b);
  v_runder int := 0;
  v_kemi   int := 0;
begin
  if not (public.is_staff() or public.is_captain()) then
    raise exception 'Kun trænere, admins og kaptajner kan rydde op'
      using errcode = '42501';
  end if;
  if p_a is null or p_b is null or p_a = p_b then
    raise exception 'Der skal angives to forskellige spillere';
  end if;

  -- De pladser hvor de to stod som makkere.
  with sammen as (
    select a.id as a_id, b.id as b_id
      from public.training_round_slots a
      join public.training_round_slots b
        on  b.round_id = a.round_id
        and b.bane     = a.bane
        and b.par      = a.par
       where a.user_id = v_lav and b.user_id = v_hoej
  ), fjernet as (
    delete from public.training_round_slots s
     where s.id in (select a_id from sammen)
        or s.id in (select b_id from sammen)
    returning 1
  )
  select count(*)::int / 2 into v_runder from fjernet;

  delete from public.par_kemi
   where spiller_lav = v_lav and spiller_hoej = v_hoej;
  get diagnostics v_kemi = row_count;

  return query select v_runder, v_kemi;
end;
$$;

revoke all on function public.slet_par_historik(uuid, uuid) from public;
grant execute on function public.slet_par_historik(uuid, uuid) to authenticated;
