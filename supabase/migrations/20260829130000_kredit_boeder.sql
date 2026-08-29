-- ── Negative bøder: kredit ("stikker-bøde") ────────────────────────────────
-- En stikker-bøde er en almindelig bødetype med et NEGATIVT beløb, uddelt på
-- helt samme måde som alle andre. Den trækker fra det skyldige beløb og kan
-- opbygge et tilgodehavende. Den udbetales aldrig.
--
-- CHECK'et krævede > 0. Det bliver til <> 0: et beløb på nul giver stadig
-- ingen mening, men minus gør nu.
--
-- Ranglisten skal ikke forvrides af kreditter:
--   • total_oere (rangeringen, "flest bøder gennem tiden") tæller kun
--     positive beløb — ellers ville man kunne stikke sig ned ad podiet.
--   • ubetalte_antal tæller kun positive — en kredit er ikke en ubetalt bøde,
--     og stikkeren skal ikke fremstå som om han har fået en.
--   • skyldigt_oere summerer ALT ubetalt, så kreditten trækker fra og
--     beløbet kan blive negativt = tilgodehavende.
--   • kredit_oere er nyt: tilgodehavendet som et positivt tal, til visning.

alter table public.fines
  drop constraint if exists fines_belob_oere_check;
alter table public.fines
  add constraint fines_belob_oere_check check (belob_oere <> 0);

alter table public.fine_types
  drop constraint if exists fine_types_belob_oere_check;
alter table public.fine_types
  add constraint fine_types_belob_oere_check check (belob_oere <> 0);

create or replace view public.fine_leaderboard as
  select p.id,
         p.navn,
         count(f.*) filter (
           where f.status = 'ubetalt'::fine_status and f.belob_oere > 0
         )::integer as ubetalte_antal,
         coalesce(sum(f.belob_oere) filter (
           where f.status = 'ubetalt'::fine_status
         ), 0::numeric) as skyldigt_oere,
         coalesce(sum(f.belob_oere) filter (
           where f.status = 'godkendt_betalt'::fine_status and f.belob_oere > 0
         ), 0::numeric) as betalt_oere,
         coalesce(sum(f.belob_oere) filter (where f.belob_oere > 0),
                  0::numeric) as total_oere,
         coalesce(-sum(f.belob_oere) filter (
           where f.status = 'ubetalt'::fine_status and f.belob_oere < 0
         ), 0::numeric) as kredit_oere
    from public.profiles p
    left join public.fines f on f.user_id = p.id
   group by p.id, p.navn;
