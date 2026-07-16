-- Per-hold MobilePay-boks: hvert hold (groups) kan have sit eget Box-ID/-link.
-- Tom/NULL = holdet bruger klubbens fælles boks fra club_config (fallback).
-- Bødekassen slår spillerens hold-boks op; admins redigerer pr. hold i Dashboard.
alter table public.groups
  add column if not exists mobilepay_box_id text;
