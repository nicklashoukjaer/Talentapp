-- ── Bænken: hvem sidder over i en runde ───────────────────────────────────
--
-- Går antallet ikke op, endte den overskydende spiller hidtil i et par med
-- én mand. Det ligner en fejl på tavlen, og det gør det umuligt at fordele
-- siddetiden retfærdigt, fordi appen ikke kan se forskel på "halvt par" og
-- "sidder over".
--
-- Bænken er nu en plads i runden som alle andre: samme række, men uden
-- bane og par. Så tæller spilleren med i runden, og næste runde kan
-- prioritere den der sad over sidst.
alter table public.training_round_slots alter column bane drop not null;
alter table public.training_round_slots alter column par  drop not null;

-- De gamle checks tillader ikke null. De erstattes af én samlet regel, så
-- en halv tilstand — bane uden par — ikke kan opstå.
alter table public.training_round_slots
  drop constraint if exists training_round_slots_bane_check;
alter table public.training_round_slots
  drop constraint if exists training_round_slots_par_check;

alter table public.training_round_slots
  drop constraint if exists slot_plads_eller_baenk;
-- num_nonnulls frem for "is null and" — og det er ikke en smagssag.
-- Med (bane is null and par is null) or (bane >= 1 and par in (1,2))
-- slipper bane=1, par=null igennem: "null in (1,2)" er NULL, ikke false,
-- og en CHECK der ender på NULL godkendes af Postgres. Det blev fanget i
-- rollback-testen. Tælles de ikke-tomme felter først, er udtrykket altid
-- sandt eller falsk — samme greb som slot_praecis_en_person bruger.
alter table public.training_round_slots
  add constraint slot_plads_eller_baenk
  check (
    num_nonnulls(bane, par) = 0                    -- sidder over
    or (num_nonnulls(bane, par) = 2                -- på banen
        and bane >= 1
        and par in (1, 2))
  );

comment on column public.training_round_slots.bane is
  'Banenummer, eller null når spilleren sidder over i runden.';
comment on column public.training_round_slots.par is
  'Par 1 eller 2 på banen, eller null når spilleren sidder over.';

-- par_overblik behøver ingen ændring: den joiner på b.bane = a.bane og
-- b.par = a.par, og null = null giver ikke sandt. To der sidder over i
-- samme runde bliver derfor ikke talt som makkere.
