-- TRIN 1 ── Spor på hvem der selv har meldt betalt ─────────────────────────
-- MobilePay melder ikke tilbage til appen, så en spiller der trykker "betal"
-- kan kun SIGE at de har betalt. Vi tror på dem — klubben er lille nok til at
-- man opdager snyd — men det skal kunne ses hvad der er godkendt af en admin
-- og hvad spilleren selv har meldt ind.
--
-- Bevidst ingen ny status: alt der filtrerer på ubetalt/godkendt_betalt
-- (rangliste, "du skylder", rykkere, "Gør op") virker uændret.

alter table public.fines
  add column if not exists selvmeldt boolean not null default false;

comment on column public.fines.selvmeldt is
  'true = spilleren markerede selv bøden betalt efter at have åbnet MobilePay. '
  'Ikke bekræftet af en admin.';
