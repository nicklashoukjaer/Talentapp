-- ── Markér bookede kampdatoer på en afstemning ──────────────────────────────
-- Når datoerne er stemt igennem og kampene bliver booket, skal man kunne
-- markere hvilke datoer der rent faktisk er booket — så holdet har ét sted at
-- se hvad der er på plads, uden at skulle huske det udenad.
--
-- Additivt: eksisterende muligheder får false og ser ud som før.

alter table public.poll_options
  add column if not exists booket boolean not null default false;

comment on column public.poll_options.booket is
  'Der er booket kamp på denne dato. Sættes af admin/træner/opretter/kaptajn; '
  'vises for alle.';

-- Hidtil kunne poll_options kun oprettes, læses og slettes — ikke opdateres.
-- Rettigheden genbruger can_manage_event() via afstemningen, så den følger
-- samme regel som at redigere og sende rykkere: staff, opretter, kaptajn.
drop policy if exists "Options: kan_manage opdaterer" on public.poll_options;
create policy "Options: kan_manage opdaterer" on public.poll_options
  for update
  using (exists (
    select 1 from public.polls p
     where p.id = poll_options.poll_id
       and public.can_manage_event(p.created_by, p.group_id, p.group_ids)))
  with check (exists (
    select 1 from public.polls p
     where p.id = poll_options.poll_id
       and public.can_manage_event(p.created_by, p.group_id, p.group_ids)));
