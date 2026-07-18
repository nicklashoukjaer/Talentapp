-- Afstemninger kan nu høre til ét hold (group), ligesom aktiviteter/trainings.
-- NULL = klub-bred (alle kan stemme). Slettes holdet, bliver afstemningen
-- klub-bred i stedet for at forsvinde (on delete set null).
alter table public.polls
  add column if not exists group_id uuid references public.groups(id) on delete set null;
