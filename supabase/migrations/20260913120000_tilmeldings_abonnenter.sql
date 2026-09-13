-- TRIN 1 ── Tabellen over hvem der følger et hold ──────────────────────────
-- Bevidst UAFHÆNGIG af medlemskab: Mads er kun medlem af Talentløse 2, men
-- skal have beskeder fra Talentløse 1 uden at blive spiller på holdet.

create table if not exists public.tilmeldings_abonnenter (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  group_id    uuid not null references public.groups(id)   on delete cascade,
  oprettet_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

alter table public.tilmeldings_abonnenter enable row level security;

drop policy if exists "tilm_abon_staff" on public.tilmeldings_abonnenter;
create policy "tilm_abon_staff" on public.tilmeldings_abonnenter
  for all using (public.is_staff()) with check (public.is_staff());

drop policy if exists "tilm_abon_egen" on public.tilmeldings_abonnenter;
create policy "tilm_abon_egen" on public.tilmeldings_abonnenter
  for select using (user_id = auth.uid());
