-- Kaptajn pr. hold: en spiller kan markeres som kaptajn af et hold.
alter table public.group_members
  add column if not exists is_captain boolean not null default false;

-- Er den aktuelle bruger kaptajn på mindst ét hold?
create or replace function public.is_captain()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.group_members
    where user_id = auth.uid() and is_captain
  );
$$;

-- Kaptajner (og staff) må oprette begivenheder og afstemninger.
alter policy "Trainings: staff opretter" on public.trainings
  with check (public.is_staff() or public.is_captain());
alter policy "Polls: staff opretter" on public.polls
  with check (public.is_staff() or public.is_captain());
alter policy "Options: staff opretter" on public.poll_options
  with check (public.is_staff() or public.is_captain());
