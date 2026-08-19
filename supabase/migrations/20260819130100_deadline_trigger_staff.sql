-- ── Trigger og RLS var ikke enige om hvem der må sætte svar for andre ───────
-- RLS på training_participants tillader can_manage_training() — altså staff,
-- opretter og kaptajn for holdet — og UI'et tilbyder dem knapperne. Men denne
-- BEFORE-trigger undtog kun is_admin(), så en træner eller kaptajn ramte
-- "Du kan kun ændre din egen tilmelding" og kunne i praksis ingenting.
--
-- Triggeren følger nu samme regel som RLS. Almindelige spillere er uændret
-- bundet til deres egen tilmelding og til tilmeldingsfristen.

create or replace function public.enforce_training_deadline()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  deadline timestamptz;
begin
  -- Må man administrere begivenheden, må man også sætte svar for andre og
  -- tilføje en afløser efter fristen — det er netop da behovet opstår.
  if public.can_manage_training(new.training_id) then
    new.updated_at := now();
    new.updated_by := auth.uid();
    return new;
  end if;

  if new.user_id <> auth.uid() then
    raise exception 'Du kan kun ændre din egen tilmelding' using errcode = '42501';
  end if;

  select tilmeldings_deadline into deadline
  from public.trainings where id = new.training_id;

  if deadline is null then
    raise exception 'Træning findes ikke' using errcode = 'P0002';
  end if;

  if now() > deadline then
    raise exception 'Tilmeldingsfristen er overskredet (%)', deadline using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' and new.status = 'venteliste' then
    raise exception 'Status venteliste sættes automatisk' using errcode = '42501';
  end if;

  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$function$;
