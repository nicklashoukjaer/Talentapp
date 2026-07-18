-- Aktiviteter kan nu høre til ét ELLER flere hold. group_ids er den nye kilde;
-- det gamle group_id beholdes for bagudkompatibilitet (appen læser group_ids
-- og falder tilbage til group_id for ældre rækker). NULL/tom = alle hold.
alter table public.trainings
  add column if not exists group_ids uuid[];

-- Migrér eksisterende enkelt-hold-aktiviteter ind i group_ids.
update public.trainings
  set group_ids = array[group_id]
  where group_id is not null
    and (group_ids is null or array_length(group_ids, 1) is null);
