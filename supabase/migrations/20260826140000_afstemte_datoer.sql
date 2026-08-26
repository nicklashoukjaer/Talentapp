-- ── Afstemte datoer som ét opslag ──────────────────────────────────────────
-- Genvejen i opret-begivenhed hentede fire tabeller og talte stemmerne i
-- appen. Det var både unødigt (fire kald for en liste på et dusin datoer) og
-- skrøbeligt: rækkegrænser, tomme opslag eller en fejl i optællingen gav en
-- tom liste uden at nogen kunne se hvorfor.
--
-- Nu regner databasen det ud og returnerer kun de datoer der kvalificerer.
-- Holdene returneres som ID'er, så filtreringen i appen kan sammenligne på
-- id frem for at matche holdnavne som tekst.

create or replace function public.afstemte_datoer(p_min integer default 4)
returns table (
  dato timestamptz,
  stemmer integer,
  hold text,
  booket boolean,
  hold_ids uuid[]
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select o.option_tid as dato,
         count(*) filter (where r.svar)::integer as stemmer,
         coalesce((select string_agg(g.navn, ' · ' order by g.navn)
                     from public.groups g
                    where g.id = any(coalesce(p.group_ids, array[p.group_id]))),
                  '') as hold,
         o.booket,
         coalesce(p.group_ids, array[p.group_id]) as hold_ids
    from public.poll_options o
    join public.polls p on p.id = o.poll_id
    left join public.poll_responses r on r.poll_option_id = o.id
   where (o.option_tid at time zone 'Europe/Copenhagen')::date >= current_date
   group by o.id, o.option_tid, o.booket, p.group_ids, p.group_id
  having count(*) filter (where r.svar) >= p_min
   order by o.option_tid;
$$;

grant execute on function public.afstemte_datoer(integer) to authenticated;
