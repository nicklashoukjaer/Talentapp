-- Bøde-administrator pr. hold: kan uddele/godkende/slette bøder for sit holds spillere.
alter table public.group_members
  add column if not exists is_fine_admin boolean not null default false;

-- Er den aktuelle bruger på mindst ét hold som bøde-admin?
create or replace function public.is_fine_admin()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.group_members
    where user_id = auth.uid() and is_fine_admin
  );
$$;

-- Må den aktuelle bruger administrere bøder for [p_target]?
--   • fuld admin: altid
--   • bøde-admin: hvis target er medlem af et hold hvor jeg er bøde-admin
create or replace function public.can_admin_fine(p_target uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select public.is_admin() or exists (
    select 1
    from public.group_members me
    join public.group_members them on them.group_id = me.group_id
    where me.user_id = auth.uid() and me.is_fine_admin
      and them.user_id = p_target
  );
$$;

-- Godkend (update) og slet (delete) må nu også gøres af holdets bøde-admin.
alter policy "Fines: admin opdaterer" on public.fines
  using (public.can_admin_fine(user_id))
  with check (public.can_admin_fine(user_id));
alter policy "Fines: admin sletter" on public.fines
  using (public.can_admin_fine(user_id));
