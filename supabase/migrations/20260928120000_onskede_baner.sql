-- Hvilke baner en hjemmekamp ØNSKES booket på.
--
-- Bane-status kommer fra Bookli gennem automations-broen, men broen kan
-- ikke gætte hvilke baner klubben vil have. D8-D12 ligger i én hal og
-- D1-D4 i en anden; valget afgør både hvor man spiller og hvad det
-- koster. Derfor skrives ønsket ned ved oprettelsen af kampen.
--
-- Tom liste = intet ønske angivet. Det er ikke det samme som "ingen
-- baner": alle kampe i historikken er oprettet før feltet fandtes, og
-- de skal ikke pludselig se forkerte ud.
alter table public.trainings
  add column if not exists onskede_baner text[] not null default '{}';

comment on column public.trainings.onskede_baner is
  'Ønskede banenavne i Bookli, fx {D10,D11,D12}. Tom = ikke angivet. '
  'Bruges af automations-broen til ledighedstjek og ombooking.';

-- Kun navne som "D10" eller "S2" — ikke fri tekst. Broen slår dem op i
-- Booklis baneliste, og en tastefejl skal fanges her frem for at ende
-- som en booking på den forkerte bane.
--
-- En CHECK må ikke indeholde en underforespørgsel, og der findes ingen
-- "alle elementer matcher"-operator. Derfor en IMMUTABLE funktion: den
-- er ren, afhænger kun af sit argument, og må derfor gerne bruges.
create or replace function public.er_banenavne(navne text[])
returns boolean
language sql
immutable
parallel safe
as $$
  select coalesce(bool_and(n ~ '^[A-Z]{1,2}[0-9]{1,2}$'), true)
  from unnest(navne) n
$$;

comment on function public.er_banenavne(text[]) is
  'Sandt hvis hvert element ligner et banenavn. Tom liste er sand.';

alter table public.trainings
  drop constraint if exists trainings_onskede_baner_format;

alter table public.trainings
  add constraint trainings_onskede_baner_format
  check (public.er_banenavne(onskede_baner));
