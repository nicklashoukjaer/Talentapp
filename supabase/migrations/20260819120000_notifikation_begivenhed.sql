-- ── Klokken kaldte alt for "træning" ────────────────────────────────────────
-- Notifikationen hed 'Ny træning: <titel>', også når begivenheden var en kamp.
-- Appen kalder dem konsekvent "begivenheder", og push-beskeden siger allerede
-- "Ny begivenhed" — kun klokken var ude af trit.
--
-- Eneste ændring i funktionen er teksten; modtagere og regler er uændrede.

create or replace function private.announce_training(t public.trainings)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_groups uuid[];
begin
  perform private.post_notify('trainings', row_to_json(t));

  v_groups := case
    when t.group_ids is not null and array_length(t.group_ids, 1) is not null
      then t.group_ids
    when t.group_id is not null then array[t.group_id]
    else null end;

  -- Holdets medlemmer (trænere inkl. — de er på holdet) plus alle admins.
  -- Klub-brede begivenheder uden hold går fortsat til alle.
  insert into public.notifications (recipient_id, kind, titel, body, data)
  select p.id,
         'training_oprettet',
         'Ny begivenhed: ' || t.titel,
         to_char(t.start_tid at time zone 'Europe/Copenhagen', 'DD.MM. HH24:MI')
           || ' – ' || t.adresse,
         jsonb_build_object('training_id', t.id)
    from public.profiles p
   where v_groups is null
      or p.rolle = 'admin'
      or exists (
           select 1 from public.group_members gm
            where gm.user_id = p.id and gm.group_id = any(v_groups));
end;
$$;

-- Ret også de beskeder der allerede ligger i folks klokke.
update public.notifications
   set titel = 'Ny begivenhed: ' || substring(titel from 13)
 where kind = 'training_oprettet' and titel like 'Ny træning: %';
