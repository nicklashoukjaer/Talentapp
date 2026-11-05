-- ── Kontakt: skal faste par bruges i DENNE træning? ──────────────────────
--
-- Faste par er holdets varige konstellationer, men en enkelt træning kan
-- have et andet formål — fx at prøve nye sammensætninger af. Hidtil kunne
-- man kun opnå det ved at slette parrene og oprette dem igen bagefter.
--
-- Står på tavlen frem for på parret: valget gælder én træning, ikke
-- holdet.
alter table public.training_boards
  add column if not exists brug_faste_par boolean not null default true;

comment on column public.training_boards.brug_faste_par is
  'Holdes faste par sammen i denne trænings runder? Standard: ja.';
