-- ── Versionstæller på runden ──────────────────────────────────────────────
--
-- En runde skrives om i sin helhed hver gang noget flyttes. Sidder to
-- trænere med den samme tavle, overskriver den sidste den første uden at
-- nogen opdager det. Tælleren gør det muligt at sige fra: appen sender den
-- version den har læst, og en skrivning på et forældet grundlag afvises.
alter table public.training_rounds
  add column if not exists version int not null default 1;

comment on column public.training_rounds.version is
  'Tælles op ved hver omskrivning. Bruges til at afvise skrivninger der '
  'bygger på en forældet opstilling.';
