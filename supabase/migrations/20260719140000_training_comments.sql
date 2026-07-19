create table if not exists public.training_comments (
  id uuid primary key default gen_random_uuid(),
  training_id uuid not null references public.trainings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists training_comments_training_idx
  on public.training_comments(training_id, created_at);
alter table public.training_comments enable row level security;
drop policy if exists tc_select on public.training_comments;
drop policy if exists tc_insert on public.training_comments;
drop policy if exists tc_delete on public.training_comments;
create policy tc_select on public.training_comments
  for select to authenticated using (true);
create policy tc_insert on public.training_comments
  for insert to authenticated with check (user_id = auth.uid());
create policy tc_delete on public.training_comments
  for delete to authenticated using (user_id = auth.uid() or public.is_staff());
