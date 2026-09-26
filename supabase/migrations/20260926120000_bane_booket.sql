-- ── Banebooking på hjemmekampe ────────────────────────────────────────────
-- En flyttet hjemmekamp betyder at banerne skal flyttes i Bookli, og det
-- bliver glemt. Feltet her giver appen noget at advare om.

alter table public.trainings
  add column if not exists bane_booket boolean not null default false;

comment on column public.trainings.bane_booket is
  'Er banerne booket i Bookli? Nulstilles automatisk når en hjemmekamp '
  'flyttes, så en flytning ikke kan overses.';

alter table public.club_config
  add column if not exists bookli_url text;

-- ── Nulstil ved flytning ──────────────────────────────────────────────────
-- Kun hjemmekampe: en udekamp har vi ikke baner til, og en træning er en
-- fast ugentlig tid. Kun tidspunktet nulstiller — en rettet titel eller
-- beskrivelse ændrer ikke på om banen står reserveret.
create or replace function public.nulstil_bane_ved_flytning()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if lower(new.titel) not like '%hjemmekamp%' then
    return new;
  end if;
  if new.start_tid is distinct from old.start_tid
     or new.slut_tid is distinct from old.slut_tid then
    new.bane_booket := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_nulstil_bane_ved_flytning on public.trainings;
create trigger trg_nulstil_bane_ved_flytning
  before update on public.trainings
  for each row execute function public.nulstil_bane_ved_flytning();

-- Afviklede begivenheder markeres som booket. Der er ingen grund til at
-- advare om baner til kampe der allerede er spillet — kun de kommende skal
-- gennemgås.
update public.trainings
   set bane_booket = true
 where start_tid < now();
