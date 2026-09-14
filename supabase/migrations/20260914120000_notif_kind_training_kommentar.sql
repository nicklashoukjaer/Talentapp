-- TRIN 1 ── Ny beskedtype. SKAL køres helt alene ───────────────────────────
alter type public.notif_kind add value if not exists 'training_kommentar';
