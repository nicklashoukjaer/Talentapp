-- ── Træner pr. hold ─────────────────────────────────────────────────────────
-- En person kan være træner for ét hold og spiller på et andet. Profil-rollen
-- 'træner' styrer fortsat RETTIGHEDER (må oprette/administrere); dette flag
-- styrer om personen TÆLLER som spiller på det enkelte hold.
--
-- Additiv: alle eksisterende rækker får false, så intet ændrer opførsel før
-- flaget sættes manuelt i admin → Medlemmer & hold.

alter table public.group_members
  add column if not exists is_trainer boolean not null default false;

comment on column public.group_members.is_trainer is
  'Træner for dette hold: tæller ikke som spiller, optager ingen spillerplads, '
  'får ikke rykkere, og vises ikke i bødekassen medmindre personen har bøder.';
