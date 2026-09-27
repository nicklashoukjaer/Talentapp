-- ── Fundament for automation-broen (fase 1) ───────────────────────────────
-- To køer som en baggrundsproces arbejder på:
--   pending_bookings — banebookinger der afventer godkendelse og udførelse
--   rankedin_sync    — hvad der mangler at blive skubbet til RankedIn
--
-- Ingen triggere og ingen ændringer i eksisterende tabeller. Appen kan ikke
-- se noget af det her endnu; det er rent fundament.
--
-- Status gemmes som text med CHECK frem for enum. En enum kræver sin egen
-- kørsel og kan ikke bruges i samme transaktion som den oprettes, og det er
-- en unødig fælde for noget der endnu kan nå at ændre sig.

-- ── Kø: banebookinger ─────────────────────────────────────────────────────
create table if not exists public.pending_bookings (
  id             uuid primary key default gen_random_uuid(),

  -- Hvad bookingen hører til. Begge kan være tomme i starten: en booking
  -- kan bestilles ud fra en afstemning FØR kampen er oprettet.
  poll_id        uuid references public.polls(id)         on delete set null,
  poll_option_id uuid references public.poll_options(id)  on delete set null,
  training_id    uuid references public.trainings(id)     on delete set null,

  oensket_start  timestamptz not null,
  oensket_slut   timestamptz not null,
  antal_baner    int not null default 1 check (antal_baner between 1 and 12),

  status         text not null default 'afventer' check (status in (
                   'afventer',    -- oprettet, venter på et menneske
                   'godkendt',    -- godkendt, klar til robotten
                   'i_gang',      -- robotten har taget den
                   'booket',      -- gennemført i Bookli
                   'afvist',      -- et menneske sagde nej
                   'fejlet'       -- robotten gav op
                 )),

  godkendt_af    uuid references public.profiles(id) on delete set null,
  godkendt_at    timestamptz,

  -- Robottens arbejdsspor. forsoeg tælles op ved hvert forsøg, så en
  -- booking ikke kan køre i ring for evigt.
  forsoeg        int not null default 0,
  sidste_fejl    text,
  ekstern_ref    text,               -- Booklis eget booking-id
  payload        jsonb not null default '{}'::jsonb,

  oprettet_af    uuid references public.profiles(id) on delete set null,
  oprettet_at    timestamptz not null default now(),
  opdateret_at   timestamptz not null default now(),

  constraint booking_slut_efter_start check (oensket_slut > oensket_start)
);

comment on table public.pending_bookings is
  'Kø over banebookinger i Bookli. Et menneske godkender; en baggrundsproces '
  'udfører. Intet bookes uden godkendelse.';

create index if not exists pending_bookings_status_idx
  on public.pending_bookings (status, oensket_start);

-- ── Kø: RankedIn ──────────────────────────────────────────────────────────
create table if not exists public.rankedin_sync (
  id           uuid primary key default gen_random_uuid(),
  slags        text not null check (slags in ('kamp', 'resultat', 'holdopstilling')),
  training_id  uuid references public.trainings(id) on delete cascade,
  ekstern_id   text,                -- RankedIns eget id, når vi kender det
  status       text not null default 'afventer' check (status in (
                 'afventer', 'i_gang', 'synkroniseret', 'fejlet'
               )),
  forsoeg      int not null default 0,
  sidste_fejl  text,
  payload      jsonb not null default '{}'::jsonb,
  oprettet_at  timestamptz not null default now(),
  opdateret_at timestamptz not null default now(),
  synket_at    timestamptz
);

comment on table public.rankedin_sync is
  'Kø over hvad der mangler at blive skubbet til RankedIn.';

create index if not exists rankedin_sync_status_idx
  on public.rankedin_sync (status, oprettet_at);

-- ── Adgang ────────────────────────────────────────────────────────────────
-- Kun staff må se og røre køerne. Baggrundsprocessen kører med service-
-- nøglen og går uden om RLS.
alter table public.pending_bookings enable row level security;
alter table public.rankedin_sync    enable row level security;

drop policy if exists "pending_bookings_staff" on public.pending_bookings;
create policy "pending_bookings_staff" on public.pending_bookings
  for all using (public.is_staff()) with check (public.is_staff());

drop policy if exists "rankedin_sync_staff" on public.rankedin_sync;
create policy "rankedin_sync_staff" on public.rankedin_sync
  for all using (public.is_staff()) with check (public.is_staff());

-- ── Hold opdateret_at ajour ───────────────────────────────────────────────
create or replace function public.roer_opdateret_at()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  -- clock_timestamp(), ikke now(): now() er transaktionens STARTtid og står
  -- stille. To opdateringer i samme transaktion ville få samme tidsstempel,
  -- og så kan man ikke se hvad der skete sidst.
  new.opdateret_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists trg_pending_bookings_opdateret on public.pending_bookings;
create trigger trg_pending_bookings_opdateret
  before update on public.pending_bookings
  for each row execute function public.roer_opdateret_at();

drop trigger if exists trg_rankedin_sync_opdateret on public.rankedin_sync;
create trigger trg_rankedin_sync_opdateret
  before update on public.rankedin_sync
  for each row execute function public.roer_opdateret_at();
