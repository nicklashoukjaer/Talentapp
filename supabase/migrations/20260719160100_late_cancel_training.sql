create or replace function public.late_cancel_training(p_training_id uuid)
returns integer  -- beløb i øre af evt. bøde (0 = ingen bøde)
language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid();
  v_deadline timestamptz;
  v_status text;
  v_type uuid;
  v_auto boolean;
  v_oere int := 0;
begin
  if v_uid is null then raise exception 'Ikke logget ind' using errcode = '42501'; end if;
  select tilmeldings_deadline into v_deadline from public.trainings where id = p_training_id;
  if v_deadline is null then raise exception 'Begivenhed findes ikke'; end if;

  select status into v_status from public.training_participants
    where training_id = p_training_id and user_id = v_uid;

  insert into public.training_participants(training_id, user_id, status)
    values (p_training_id, v_uid, 'afmeldt')
    on conflict (training_id, user_id) do update set status = 'afmeldt';

  -- Bøde kun hvis: frist overskredet, auto slået til, type valgt, og man var tilmeldt/venteliste.
  if now() > v_deadline and coalesce(v_status,'') in ('tilmeldt','venteliste') then
    select noshow_fine_type_id, noshow_auto_enabled into v_type, v_auto
      from public.club_config where id = 1;
    if coalesce(v_auto,false) and v_type is not null then
      insert into public.fines(user_id, given_by, fine_type_id, begrundelse)
        values (v_uid, v_uid, v_type, 'Sent afbud');
      select belob_oere into v_oere from public.fine_types where id = v_type;
    end if;
  end if;
  return coalesce(v_oere, 0);
end $$;
grant execute on function public.late_cancel_training(uuid) to authenticated;
