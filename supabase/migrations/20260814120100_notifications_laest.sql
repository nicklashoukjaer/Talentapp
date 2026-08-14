-- ── Læst-status på notifikationer ───────────────────────────────────────────
-- Klokkens ulæst-tælling lå i browserens localStorage. Det var pr. enhed, gik
-- tabt når lagringen blev ryddet (bl.a. rutinemæssigt på iOS), og kunne ikke
-- gøres bedre: der fandtes kun SELECT-politikker på notifications, så appen
-- havde ikke lov til at skrive status nogen steder.
--
-- Nu ligger status på rækken. laest_at = null betyder ulæst.

alter table public.notifications
  add column if not exists laest_at timestamptz;

comment on column public.notifications.laest_at is
  'Hvornår modtageren har set notifikationen. null = ulæst.';

-- Ulæst-tællingen er det eneste hyppige opslag.
create index if not exists notifications_unread_idx
  on public.notifications (recipient_id) where laest_at is null;

-- Alt eksisterende markeres som læst. Der findes ingen pålidelig historik over
-- hvad folk faktisk har set (den lå lokalt på deres enheder), og alternativet
-- ville være at hele klubben vågnede op til en badge med 9+.
update public.notifications set laest_at = now() where laest_at is null;

-- Man må opdatere sine egne notifikationer — og kun sine egne. with check
-- forhindrer at en række flyttes til en anden modtager.
drop policy if exists "notif_update_own" on public.notifications;
create policy "notif_update_own" on public.notifications
  for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());
