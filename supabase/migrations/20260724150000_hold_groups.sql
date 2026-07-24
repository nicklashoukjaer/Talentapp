-- Holdgrupper: saml hold der deler bødekasse/bødetyper/MobilePay.
create table if not exists public.hold_groups (
  id uuid primary key default gen_random_uuid(),
  navn text not null check (char_length(navn) between 1 and 60),
  mobilepay_box_id text,
  created_at timestamptz not null default now()
);
alter table public.groups
  add column if not exists hold_group_id uuid
    references public.hold_groups(id) on delete set null;

alter table public.hold_groups enable row level security;
drop policy if exists hg_read on public.hold_groups;
drop policy if exists hg_write on public.hold_groups;
create policy hg_read on public.hold_groups for select to authenticated using (true);
create policy hg_write on public.hold_groups for all to authenticated
  using (public.is_staff()) with check (public.is_staff());
