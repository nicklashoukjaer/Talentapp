-- Kun en admin må tildele eller fjerne admin-rollen. Trænere kan skifte mellem
-- spiller/træner, men ikke oprette eller nedgradere en admin.
create or replace function public.enforce_admin_role_change()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.rolle is distinct from old.rolle
     and (new.rolle = 'admin' or old.rolle = 'admin')
     and not public.is_admin() then
    raise exception 'Kun en admin kan tildele eller fjerne admin-rollen'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_enforce_admin_role on public.profiles;
create trigger trg_enforce_admin_role
  before update on public.profiles
  for each row execute function public.enforce_admin_role_change();
