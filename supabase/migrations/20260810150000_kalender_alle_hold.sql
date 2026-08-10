-- ── Kalender-feed for hele klubben, pr. bruger ──────────────────────────────
-- Enkelte personer har brug for at se HELE klubbens program i deres kalender
-- uden at være medlem af holdene i appen — fx en pårørende der deler kalender
-- med et medlem.
--
-- Flaget påvirker UDELUKKENDE edge-funktionen `calendar-feed`. Det giver ikke
-- adgang til noget i appen: ingen afstemninger, ingen bødekasse, ingen
-- notifikationer, og personen tæller ikke med på noget hold. Al anden logik
-- slår fortsat op i group_members.
--
-- Synlighedsreglen gælder stadig: uudgivne begivenheder (synlig_fra i
-- fremtiden) kommer først med når de bliver synlige — medmindre personen er
-- staff, præcis som i appen.
--
-- Der er bevidst ingen knap til det i UI'et; det er en undtagelse der sættes
-- direkte i databasen:
--   update public.profiles set kalender_alle_hold = true where id = '<uuid>';

alter table public.profiles
  add column if not exists kalender_alle_hold boolean not null default false;

comment on column public.profiles.kalender_alle_hold is
  'Kalender-feedet (.ics) viser hele klubbens begivenheder, ikke kun personens '
  'egne hold. Påvirker KUN calendar-feed — ikke rettigheder, afstemninger, '
  'bødekasse, notifikationer eller holdtilknytning.';
