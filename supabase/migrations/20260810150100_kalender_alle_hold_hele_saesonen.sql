-- kalender_alle_hold dækker nu også hele sæsonen — altså begivenheder der
-- endnu ikke er udgivet til spillerne (synlig_fra i fremtiden). Formålet er at
-- kunne følge den planlagte sæson i en ekstern kalender.
--
-- Vær opmærksom på at flaget dermed viser klubbens planlægning til den der har
-- det, før medlemmerne selv kan se den i appen. Sæt det kun på folk der må se
-- planlægningen.

comment on column public.profiles.kalender_alle_hold is
  'Kalender-feedet (.ics) viser hele klubbens begivenheder for hele sæsonen — '
  'også endnu ikke udgivne. Påvirker KUN calendar-feed: ikke rettigheder, '
  'afstemninger, bødekasse, notifikationer eller holdtilknytning.';
