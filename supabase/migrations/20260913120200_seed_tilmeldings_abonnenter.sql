-- TRIN 4 ── Opsætning: Mads følger T1 + T2, Betina følger Damer ────────────
-- Navnene står KUN her. Bagefter styres det fra appen under
-- Admin → Medlemmer & hold → hold → "Besked ved til-/afmelding".

insert into public.tilmeldings_abonnenter (user_id, group_id)
select p.id, g.id
  from public.profiles p
  cross join public.groups g
 where (p.navn = 'Mads Houkjær'
        and g.navn in ('Talentløse 1', 'Talentløse 2'))
    or (p.navn = 'Betina Valentin Staal'
        and g.navn = 'Talentløse Damer')
on conflict do nothing;

select p.navn, g.navn as hold
  from public.tilmeldings_abonnenter a
  join public.profiles p on p.id = a.user_id
  join public.groups   g on g.id = a.group_id
 order by p.navn, g.navn;
