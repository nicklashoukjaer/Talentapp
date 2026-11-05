-- ── Hvilken runde kører lige nu? ─────────────────────────────────────────
--
-- Træneren kan nu forberede flere runder før træningen. Hidtil var "den
-- aktuelle runde" simpelthen den med det højeste nummer — men når runde
-- 1, 2 og 3 alle findes fra start, ville spillerne få runde 3 at se mens
-- holdet stod og spillede runde 1.
--
-- Tavlen peger derfor eksplicit på den runde der afvikles. Null betyder
-- "den højeste", som før, så gamle tavler opfører sig uændret.
alter table public.training_boards
  add column if not exists aktiv_runde int check (aktiv_runde is null or aktiv_runde >= 1);

comment on column public.training_boards.aktiv_runde is
  'Rundenummeret der afvikles nu. Null = den højeste, som før.';
