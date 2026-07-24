-- Bødetyper kan høre til et fællesskab: en holdgruppe ELLER et selvstændigt
-- hold. Begge NULL = fælles (gælder alle hold).
alter table public.fine_types
  add column if not exists hold_group_id uuid references public.hold_groups(id) on delete cascade,
  add column if not exists group_id uuid references public.groups(id) on delete cascade;
