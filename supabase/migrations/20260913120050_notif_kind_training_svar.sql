-- TRIN 2 ── Ny beskedtype. SKAL køres helt alene ───────────────────────────
-- Postgres tillader ikke at BRUGE en ny enum-værdi i samme transaktion som
-- den oprettes, og enkelte opsætninger afviser den helt inde i en transaktion.
-- Derfor står den her som den eneste sætning i sin egen kørsel.

alter type public.notif_kind add value if not exists 'training_svar';
