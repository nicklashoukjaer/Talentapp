-- Synlighed pr. aktivitet: en aktivitet bliver først synlig for spillere når
-- synlig_fra er passeret (eller er NULL = straks synlig). Staff (admin/træner)
-- ser altid alt. Filtreringen sker klient-side i appen — dette er kun oprydning
-- af overblikket, ikke følsomme data, så ingen RLS-ændring er nødvendig.
alter table public.trainings
  add column if not exists synlig_fra timestamptz;
