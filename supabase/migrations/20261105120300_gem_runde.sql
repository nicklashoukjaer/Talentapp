-- ── Skriv en hel runde i én transaktion ──────────────────────────────────
--
-- Appen skrev før runden om i to trin: slet alle pladser, indsæt dem igen.
-- Mislykkedes indsættelsen — netværket, en afmeldt spiller, hvad som helst
-- — stod runden tilbage TOM. Midt i en træning.
--
-- Her sker begge dele i ét kald, så runden enten er den gamle eller den
-- nye. Samtidig tjekkes versionen: har en anden træner ændret runden
-- imens, afvises skrivningen frem for at overskrive den ubemærket.
--
-- @param p_slots  Array af {bane, par, laast, user_id, guest_id}. bane og
--                 par er null for dem der sidder over.
-- @param p_version Den version appen læste. null = spring tjekket over.
-- @returns Den nye version.
create or replace function public.gem_runde(
  p_round_id uuid,
  p_slots    jsonb,
  p_version  int default null
)
returns int
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_training uuid;
  v_version  int;
begin
  -- FOR UPDATE: to samtidige kald står i kø i stedet for at læse den
  -- samme version og begge tro at de er først.
  select training_id, version
    into v_training, v_version
    from public.training_rounds
   where id = p_round_id
   for update;

  if not found then
    raise exception 'Runden findes ikke' using errcode = 'P0002';
  end if;

  -- SECURITY DEFINER går uden om RLS, så adgangen skal tjekkes her.
  -- Samme regel som at redigere selve træningen.
  if not public.can_manage_training(v_training) then
    raise exception 'Du må ikke ændre denne trænings tavle'
      using errcode = '42501';
  end if;

  if p_version is not null and p_version <> v_version then
    raise exception
      'Tavlen er ændret af en anden imens. Hent den forfra og prøv igen.'
      using errcode = '40001';
  end if;

  delete from public.training_round_slots where round_id = p_round_id;

  insert into public.training_round_slots
         (round_id, bane, par, laast, user_id, guest_id)
  select p_round_id,
         nullif(e->>'bane', '')::int,
         nullif(e->>'par',  '')::int,
         coalesce((e->>'laast')::boolean, false),
         nullif(e->>'user_id',  '')::uuid,
         nullif(e->>'guest_id', '')::uuid
    from jsonb_array_elements(coalesce(p_slots, '[]'::jsonb)) e;

  update public.training_rounds
     set version = version + 1
   where id = p_round_id
   returning version into v_version;

  return v_version;
end;
$$;

revoke all on function public.gem_runde(uuid, jsonb, int) from public;
grant execute on function public.gem_runde(uuid, jsonb, int) to authenticated;

comment on function public.gem_runde(uuid, jsonb, int) is
  'Erstatter alle pladser i en runde atomart, med versionstjek.';
