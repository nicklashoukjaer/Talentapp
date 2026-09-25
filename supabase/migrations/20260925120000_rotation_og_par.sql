-- ── Roteringstavle og par-overblik ─────────────────────────────────────────
-- Fire nye tabeller og ét view. Intet eksisterende ændres.

-- Opsætningen for én trænings tavle. Én tavle pr. træning.
create table if not exists public.training_boards (
  training_id uuid primary key references public.trainings(id) on delete cascade,
  tilstand    text not null default 'mixet'
              check (tilstand in ('mixet', 'opdelt')),
  afvikling   text not null default 'manuel'
              check (afvikling in ('manuel', 'timer')),
  minutter    int  not null default 15 check (minutter between 1 and 120),
  baner       int  not null default 2  check (baner between 1 and 12),
  oprettet_af uuid references public.profiles(id) on delete set null,
  oprettet_at timestamptz not null default now()
);

-- En runde på tavlen.
create table if not exists public.training_rounds (
  id          uuid primary key default gen_random_uuid(),
  training_id uuid not null references public.trainings(id) on delete cascade,
  nr          int  not null check (nr >= 1),
  startet_at  timestamptz,
  slutter_at  timestamptz,
  oprettet_at timestamptz not null default now(),
  unique (training_id, nr)
);

-- Hvem står hvor i en runde. Et par er (round_id, bane, par):
-- to rækker deler de tre, og er dermed makkere.
-- Afløsere uden profil sidder på guest_id i stedet for user_id.
create table if not exists public.training_round_slots (
  id       uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.training_rounds(id) on delete cascade,
  bane     int  not null check (bane >= 1),
  par      int  not null check (par in (1, 2)),
  user_id  uuid references public.profiles(id)        on delete cascade,
  guest_id uuid references public.training_guests(id) on delete cascade,
  constraint slot_praecis_en_person check (num_nonnulls(user_id, guest_id) = 1),
  unique (round_id, user_id),
  unique (round_id, guest_id)
);

create index if not exists training_round_slots_round_idx
  on public.training_round_slots (round_id, bane, par);

-- Trænerens stjernemarkering. Parret gemmes sorteret, så (A,B) og (B,A)
-- er samme række og ikke kan blive markeret to gange.
create table if not exists public.par_kemi (
  spiller_lav  uuid not null references public.profiles(id) on delete cascade,
  spiller_hoej uuid not null references public.profiles(id) on delete cascade,
  markeret_af  uuid references public.profiles(id) on delete set null,
  markeret_at  timestamptz not null default now(),
  primary key (spiller_lav, spiller_hoej),
  constraint par_sorteret check (spiller_lav < spiller_hoej)
);

-- ── Adgang ────────────────────────────────────────────────────────────────
-- Læsning: alle indloggede, som med bøder og svarmuligheder.
-- Skrivning: den der må styre begivenheden — samme regel som redigering
-- og sletning af selve træningen.
alter table public.training_boards      enable row level security;
alter table public.training_rounds      enable row level security;
alter table public.training_round_slots enable row level security;
alter table public.par_kemi             enable row level security;

drop policy if exists "boards_laes" on public.training_boards;
create policy "boards_laes" on public.training_boards
  for select using (auth.uid() is not null);
drop policy if exists "boards_styr" on public.training_boards;
create policy "boards_styr" on public.training_boards
  for all using (public.can_manage_training(training_id))
      with check (public.can_manage_training(training_id));

drop policy if exists "rounds_laes" on public.training_rounds;
create policy "rounds_laes" on public.training_rounds
  for select using (auth.uid() is not null);
drop policy if exists "rounds_styr" on public.training_rounds;
create policy "rounds_styr" on public.training_rounds
  for all using (public.can_manage_training(training_id))
      with check (public.can_manage_training(training_id));

drop policy if exists "slots_laes" on public.training_round_slots;
create policy "slots_laes" on public.training_round_slots
  for select using (auth.uid() is not null);
drop policy if exists "slots_styr" on public.training_round_slots;
create policy "slots_styr" on public.training_round_slots
  for all using (exists (
        select 1 from public.training_rounds r
         where r.id = round_id and public.can_manage_training(r.training_id)))
      with check (exists (
        select 1 from public.training_rounds r
         where r.id = round_id and public.can_manage_training(r.training_id)));

drop policy if exists "kemi_laes" on public.par_kemi;
create policy "kemi_laes" on public.par_kemi
  for select using (auth.uid() is not null);
drop policy if exists "kemi_styr" on public.par_kemi;
create policy "kemi_styr" on public.par_kemi
  for all using (public.is_staff() or public.is_captain())
      with check (public.is_staff() or public.is_captain());

-- ── Par-overblik ──────────────────────────────────────────────────────────
-- Hvem har spillet sammen, hvor ofte, og har træneren markeret dem.
-- Par der kun er stjernemarkeret — men aldrig har spillet — er med, så en
-- markering ikke forsvinder ud af oversigten.
create or replace view public.par_overblik as
with spillet as (
  select least(a.user_id, b.user_id)    as spiller_lav,
         greatest(a.user_id, b.user_id) as spiller_hoej,
         count(*)                       as runder
    from public.training_round_slots a
    join public.training_round_slots b
      on  b.round_id = a.round_id
      and b.bane     = a.bane
      and b.par      = a.par
      and b.user_id  > a.user_id
   where a.user_id is not null
   group by 1, 2
),
alle as (
  select spiller_lav, spiller_hoej from spillet
  union
  select spiller_lav, spiller_hoej from public.par_kemi
)
select al.spiller_lav,
       al.spiller_hoej,
       coalesce(s.runder, 0)          as runder_sammen,
       (k.spiller_lav is not null)    as god_kemi,
       k.markeret_at
  from alle al
  left join spillet  s on s.spiller_lav = al.spiller_lav
                      and s.spiller_hoej = al.spiller_hoej
  left join public.par_kemi k on k.spiller_lav  = al.spiller_lav
                             and k.spiller_hoej = al.spiller_hoej;
