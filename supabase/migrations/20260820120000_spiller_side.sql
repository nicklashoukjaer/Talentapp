-- ── Foretrukken banehalvdel ─────────────────────────────────────────────────
-- I padel spiller man venstre eller højre side (eller begge). Skal man stille
-- hold, er det afgørende at vide — og det stod hidtil kun i folks hoveder.
--
-- Spilleren sætter selv sin side i Min profil; staff kan sætte den for dem der
-- ikke har gjort det. Begge dele er allerede dækket af RLS på profiles:
-- "Ejer eller admin kan opdatere" = auth.uid() = id or is_staff().
--
-- null = ikke angivet. Additivt; ingen eksisterende rækker ændres.

alter table public.profiles
  add column if not exists spiller_side text;

alter table public.profiles
  drop constraint if exists profiles_spiller_side_check;
alter table public.profiles
  add constraint profiles_spiller_side_check
  check (spiller_side is null or spiller_side in ('venstre', 'hoejre', 'begge'));

comment on column public.profiles.spiller_side is
  'Foretrukken banehalvdel: venstre / hoejre / begge. null = ikke angivet.';
