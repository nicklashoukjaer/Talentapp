-- ── Dato-muligheder uden klokkeslæt ─────────────────────────────────────────
-- En afstemning kunne kun spørge til dato + tid, fordi hver mulighed gemmes som
-- et fuldt tidsstempel (poll_options.option_tid). Vil man bare spørge "hvilke
-- dage kan du?", var man nødt til at finde på et klokkeslæt.
--
-- Heldags-muligheder gemmes fortsat i option_tid (kl. 00:00 lokal tid), så
-- sortering og alt eksisterende opslag virker uændret. Flaget styrer alene om
-- klokkeslættet vises.
--
-- Additivt: eksisterende muligheder får false og ser ud præcis som før.

alter table public.poll_options
  add column if not exists heldags boolean not null default false;

comment on column public.poll_options.heldags is
  'Muligheden gælder hele dagen — option_tid er sat til 00:00 og '
  'klokkeslættet skal ikke vises.';
