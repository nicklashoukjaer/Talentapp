-- ── Broen fra en afsluttet afstemning til en banebooking ──────────────────
-- Når en dato-afstemning er lukket, er de mest opbakkede datoer kandidater
-- til en kamp. Her findes de datoer der mangler noget: ingen kamp oprettet,
-- ingen booking i kø.
--
-- Kun et opslag — intet oprettes automatisk. Et menneske skal godkende,
-- og det er hele pointen med pending_bookings.

create or replace view public.afstemninger_klar_til_booking as
with lukkede as (
  select p.id, p.titel, p.lukket_at,
         coalesce(p.group_ids, array[p.group_id]) as hold
    from public.polls p
   where p.type is distinct from 'tekst'
     and p.lukket_at is not null
     and p.lukket_at <= now()
),
stemmer as (
  select o.id as option_id, o.poll_id, o.option_tid, o.heldags, o.booket,
         count(*) filter (where r.svar) as ja
    from public.poll_options o
    left join public.poll_responses r on r.poll_option_id = o.id
   group by o.id, o.poll_id, o.option_tid, o.heldags, o.booket
)
select l.id                as poll_id,
       l.titel             as afstemning,
       l.hold,
       s.option_id,
       s.option_tid,
       s.heldags,
       s.ja                as antal_ja,
       s.booket            as markeret_booket,
       exists (
         select 1 from public.pending_bookings b
          where b.poll_option_id = s.option_id
            and b.status in ('afventer', 'godkendt', 'i_gang', 'booket')
       )                   as booking_i_koe
  from lukkede l
  join stemmer s on s.poll_id = l.id
 where s.option_tid >= now()          -- fremtidige datoer; fortiden er ligegyldig
   and s.ja >= 4                      -- samme grænse som "opret kamp fra dato"
 order by l.lukket_at desc, s.ja desc, s.option_tid;

comment on view public.afstemninger_klar_til_booking is
  'Afsluttede dato-afstemninger hvis opbakkede datoer endnu mangler en '
  'banebooking. Kun et opslag — intet oprettes automatisk.';
