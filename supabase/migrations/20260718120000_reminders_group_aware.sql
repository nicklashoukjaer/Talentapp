CREATE OR REPLACE FUNCTION public.send_training_reminders(p_training_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int;
  v_titel text;
  v_group_ids uuid[];
begin
  if not public.is_admin() then
    raise exception 'Kun admins kan sende rykkere' using errcode = '42501';
  end if;

  -- Aktivitetens hold: nye rækker bruger group_ids, ældre falder tilbage til
  -- group_id. NULL = klub-bred (rammer alle, som før).
  select titel,
         case
           when group_ids is not null and array_length(group_ids, 1) is not null
             then group_ids
           when group_id is not null then array[group_id]
           else null
         end
    into v_titel, v_group_ids
  from public.trainings
  where id = p_training_id;

  with non_responders as (
    select p.id
    from public.profiles p
    where not exists (
      select 1 from public.training_participants tp
      where tp.training_id = p_training_id and tp.user_id = p.id
    )
    and (
      v_group_ids is null  -- klub-bred aktivitet: alle der mangler svar
      or exists (
        select 1 from public.group_members gm
        where gm.user_id = p.id and gm.group_id = any(v_group_ids)
      )
    )
  )
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select id, 'training_rykker',
         'Rykker: ' || v_titel,
         'Du mangler at svare på tilmelding',
         jsonb_build_object('training_id', p_training_id)
  from non_responders;

  get diagnostics v_count = row_count;
  return v_count;
end $function$;
