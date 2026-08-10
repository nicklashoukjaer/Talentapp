-- ── Afstemninger kan gælde flere hold ───────────────────────────────────────
-- Før kunne en afstemning kun høre til ÉT hold (polls.group_id). Nu bruger de
-- samme mønster som begivenheder: group_ids[] er sandheden, group_id udfyldes
-- kun når der er præcis ét hold, så ældre kode der læser den stadig virker.
--
-- Rent additivt: eksisterende afstemninger har group_ids = null og læses
-- fortsat via group_id-fallbacken (samme regel som i `_trainingGroupIds`).
--
-- Bemærk at edge-funktionen `notify` allerede læser group_ids før group_id,
-- så notifikationer for en afstemning til flere hold rammer begge holds
-- medlemmer uden yderligere ændringer.

alter table public.polls
  add column if not exists group_ids uuid[];

comment on column public.polls.group_ids is
  'Hold afstemningen gælder. null/tom = klub-bred. group_id holdes synkron '
  'når der kun er ét hold, af hensyn til ældre læsere.';

-- Gør opslag "hører denne afstemning til et af mine hold?" billigt.
create index if not exists polls_group_ids_idx
  on public.polls using gin (group_ids);
