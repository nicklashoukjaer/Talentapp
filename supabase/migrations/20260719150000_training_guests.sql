create table if not exists public.training_guests (
  id uuid primary key default gen_random_uuid(),
  training_id uuid not null references public.trainings(id) on delete cascade,
  navn text not null check (char_length(navn) between 1 and 80),
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists training_guests_training_idx
  on public.training_guests(training_id);
alter table public.training_guests enable row level security;
drop policy if exists tg_select on public.training_guests;
drop policy if exists tg_insert on public.training_guests;
drop policy if exists tg_delete on public.training_guests;
create policy tg_select on public.training_guests
  for select to authenticated using (true);
create policy tg_insert on public.training_guests
  for insert to authenticated with check (public.is_staff() and added_by = auth.uid());
create policy tg_delete on public.training_guests
  for delete to authenticated using (public.is_staff());
