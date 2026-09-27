-- ── RankedIn-link pr. hold ────────────────────────────────────────────────
-- RankedIn opretter nye hold-id'er hver sæson. Linket hører derfor til
-- holdet og skal kunne rettes af en admin i appen — ikke ligge i en .env-fil
-- på den maskine der tilfældigvis kører robotten.

alter table public.groups
  add column if not exists rankedin_url text;

comment on column public.groups.rankedin_url is
  'Holdets side på RankedIn i den aktuelle sæson. Skiftes ved sæsonstart '
  'fra Admin → Medlemmer & hold → holdet.';

-- Nuværende sæson.
update public.groups
   set rankedin_url = 'https://www.rankedin.com/en/team/homepage/3281091'
 where navn = 'Talentløse 1' and rankedin_url is null;

update public.groups
   set rankedin_url = 'https://www.rankedin.com/en/team/homePage/3280677'
 where navn = 'Talentløse 2' and rankedin_url is null;
