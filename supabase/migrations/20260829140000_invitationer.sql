-- ── Invitations-links i stedet for en fælles klubkode ──────────────────────
-- Klubkoden stod hårdkodet i kildekoden og var dermed i git. Alle delte den
-- samme, og en ny spiller skulle sættes på hold manuelt bagefter.
--
-- Et invitations-link gælder ét hold og kan bruges ÉN gang. Bliver linket
-- delt videre, virker det ikke for nummer to.
--
-- Holdet i linket er kun et udgangspunkt: bagefter er personen et almindeligt
-- medlem, som kan flyttes eller sættes på flere hold som hidtil.

create table if not exists public.invites (
  token       uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  oprettet_af uuid references public.profiles(id) on delete set null,
  oprettet_at timestamptz not null default now(),
  brugt_at    timestamptz,
  brugt_af    uuid references public.profiles(id) on delete set null
);

comment on table public.invites is
  'Engangs-invitationer til at oprette sig på et bestemt hold. brugt_at != null = opbrugt.';

alter table public.invites enable row level security;

-- Kun staff må oprette og se invitationer. Selve indløsningen sker gennem
-- funktionerne herunder, som kører security definer.
drop policy if exists "invites_staff" on public.invites;
create policy "invites_staff" on public.invites
  for all using (public.is_staff()) with check (public.is_staff());

-- ── Slå en invitation op UDEN at være logget ind ───────────────────────────
-- Bruges af oprettelses-skærmen til at vise hvilket hold man lander på.
-- Returnerer intet følsomt: kun holdets navn og om linket stadig er gyldigt.
create or replace function public.invite_info(p_token uuid)
returns table (gyldig boolean, hold text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select (i.brugt_at is null) as gyldig, g.navn as hold
    from public.invites i
    join public.groups g on g.id = i.group_id
   where i.token = p_token;
$$;

grant execute on function public.invite_info(uuid) to anon, authenticated;

-- ── Indløs invitationen efter oprettelse ───────────────────────────────────
-- Kaldes af den nyoprettede bruger selv. Sætter dem på holdet og markerer
-- linket som brugt. Er det allerede brugt, sker der intet.
create or replace function public.indloes_invite(p_token uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_group uuid;
  v_navn text;
begin
  if auth.uid() is null then
    raise exception 'Du skal være logget ind' using errcode = '42501';
  end if;

  -- Lås rækken, så to samtidige forsøg ikke begge kan bruge den.
  select i.group_id into v_group
    from public.invites i
   where i.token = p_token and i.brugt_at is null
   for update;

  if v_group is null then
    raise exception 'Invitationen er brugt eller findes ikke'
      using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id, is_captain, is_trainer)
  values (v_group, auth.uid(), false, false)
  on conflict do nothing;

  update public.invites
     set brugt_at = now(), brugt_af = auth.uid()
   where token = p_token;

  select navn into v_navn from public.groups where id = v_group;
  return v_navn;
end;
$$;

grant execute on function public.indloes_invite(uuid) to authenticated;
