-- ── Faste par (Lunar-konstellationer) ────────────────────────────────────
--
-- Trænerens varige par PR. HOLD: T1 og T2 har hver deres konstellationer,
-- og de samme to spillere kan derfor godt være faste på ét hold uden at
-- være det på et andet.
--
-- Det er IKKE det samme som `par_kemi`. Kemien er et blødt signal der
-- vægter i fordelingen; et fast par er en bindende sammensætning der ikke
-- må splittes, når runderne dannes.
create table if not exists public.faste_par (
  group_id     uuid not null references public.groups(id)   on delete cascade,
  spiller_lav  uuid not null references public.profiles(id) on delete cascade,
  spiller_hoej uuid not null references public.profiles(id) on delete cascade,

  -- Valgfrit navn, fx "Lunar 1". Tomt felt er helt i orden — parret
  -- kendes på de to navne.
  navn         text check (navn is null or char_length(navn) between 1 and 60),

  -- Slået fra frem for slettet, så en konstellation kan hvile en sæson
  -- uden at man skal huske hvem der stod i den.
  aktiv        boolean not null default true,

  oprettet_af  uuid references public.profiles(id) on delete set null,
  oprettet_at  timestamptz not null default now(),

  primary key (group_id, spiller_lav, spiller_hoej),
  -- Sorteret som par_kemi, så (A,B) og (B,A) er samme række.
  constraint faste_par_sorteret check (spiller_lav < spiller_hoej)
);

comment on table public.faste_par is
  'Faste par pr. hold. Holdes sammen når runder dannes — i modsætning til '
  'par_kemi, der kun vægter.';

-- ── Én spiller, ét fast par pr. hold ──────────────────────────────────────
--
-- Uden dette kunne både (Kesse, Fuglsang) og (Kesse, NH) stå som faste på
-- T1, og så er der ingen fordeling der kan opfylde begge. Spilleren kan
-- stå som `lav` i det ene par og `hoej` i det andet, så et unikt indeks
-- rækker ikke — derfor en trigger.
create or replace function public.tjek_fast_par_entydigt()
returns trigger
language plpgsql
as $$
declare
  v_navn text;
begin
  if not new.aktiv then
    return new;
  end if;

  select p.navn into v_navn
    from public.faste_par f
    join public.profiles p
      on p.id = case
                  when f.spiller_lav  in (new.spiller_lav, new.spiller_hoej)
                    then f.spiller_lav
                  else f.spiller_hoej
                end
   where f.group_id = new.group_id
     and f.aktiv
     and (f.spiller_lav, f.spiller_hoej)
         is distinct from (new.spiller_lav, new.spiller_hoej)
     and (f.spiller_lav  in (new.spiller_lav, new.spiller_hoej)
       or f.spiller_hoej in (new.spiller_lav, new.spiller_hoej))
   limit 1;

  if v_navn is not null then
    raise exception
      '% er allerede i et fast par på holdet. Fjern det første par først.',
      v_navn
      using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fast_par_entydigt on public.faste_par;
create trigger trg_fast_par_entydigt
  before insert or update on public.faste_par
  for each row execute function public.tjek_fast_par_entydigt();

-- ── Adgang ────────────────────────────────────────────────────────────────
-- Samme regel som par_kemi: alle indloggede må se dem, kun trænere, admins
-- og kaptajner må ændre dem.
alter table public.faste_par enable row level security;

drop policy if exists "faste_par_laes" on public.faste_par;
create policy "faste_par_laes" on public.faste_par
  for select using (auth.uid() is not null);

drop policy if exists "faste_par_styr" on public.faste_par;
create policy "faste_par_styr" on public.faste_par
  for all using (public.is_staff() or public.is_captain())
      with check (public.is_staff() or public.is_captain());
