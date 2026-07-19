alter table public.club_config
  add column if not exists noshow_fine_type_id uuid references public.fine_types(id) on delete set null,
  add column if not exists noshow_auto_enabled boolean not null default false;
