# De Talentløse Hjørring — App-overblik (nuværende tilstand)

Dette dokument beskriver klub-appen **De Talentløse Hjørring** som den er bygget
og kører i produktion i dag. Formålet er at give en designer/AI fuldt indblik i
arkitektur, skærme, funktioner, roller og datamodel — som grundlag for at
diskutere optimeringer eller nye funktioner.

> Sidst opdateret: juli 2026. Vedligeholdes manuelt — spørg hvis noget virker forældet.

---

## 1. Hvad appen er

En mobil-først **PWA** til en padel/badminton-klub. Medlemmer ser aktiviteter
(træninger/kampe), tilmelder/melder afbud, følger en bøde-highscore
("Bødekassen"), stemmer i afstemninger og styrer egen profil. Staff (admin/
træner) og hold-roller (kaptajn/bøde-admin) styrer klubben fra appen — der er
**ingen separat admin-webportal**; alt foregår i samme app, gated på rolle.

**Klubben har flere hold** (fx "Talentløse 1", "Talentløse 2", "Talentløse
Damer") + evt. grupper på tværs (kamp-trup). Næsten alt indhold kan knyttes til
ét eller flere hold.

---

## 2. Teknik & arkitektur

- **Flutter (web)**, bygget med `--wasm` (skwasm-renderer). Deployes som PWA.
- **Hosting/CI:** GitHub Actions → Vercel (`de-talentlose.vercel.app`). Auto-
  deploy ved push til `main`.
- **Backend:** Supabase (Postgres + Auth + RLS + edge functions + pg_cron).
- **Push:** OneSignal (native) + web-push via `web/index.html`. iOS web-push er
  upålideligt → in-app notifikations-klokke er den pålidelige kanal.
- **Kodestruktur:** ét Dart-bibliotek. `lib/main.dart` er roden; alle views er
  `part of '../main.dart'` (så private medlemmer deles på tværs af filer).
  - `lib/core/theme.dart` — design-tokens + ThemeData.
  - `lib/core/utils.dart` — hjælpere (dato-formattering, skeleton-loaders,
    tom-tilstande, fejl-view).
  - `lib/services/` — Supabase-klient, cache, config (MobilePay/no-show),
    kalender-feed, notifikationer.
  - `lib/views/` — én fil pr. skærm/område (login, home_shell, oversigt,
    afstemninger, bodekasse, dashboard, profil, board, common_fields).
- **Offline-venligt:** mange skærme viser cachet data straks (CacheService) og
  opdaterer i baggrunden.

---

## 3. Design-system (skal følges)

Mørkt, varmt tema. Terracotta-accent. Barlow / Barlow Condensed.

### Farver
| Token | Hex | Brug |
|---|---|---|
| bg | `#161210` | App-baggrund |
| header | `#241914` | Top-bar / nav |
| card | `#211A16` | Kort/paneler |
| card2 (elevated) | `#2A211C` | Nested, inputs, dato-blok |
| border | `rgba(255,255,255,.08)` | Hårfine streger |
| text | `#F3ECE4` | Primær tekst (varm off-white) |
| muted | `#A2968B` | Sekundær tekst |
| hint | `#8B8079` | Hint/inaktiv |
| **accent** | `#E8622C` | Primær handling/branding (terracotta) |
| success | `#34C759` | Tilmeldt/betalt/deltog (tekst på grøn `#08210F`) |
| danger | `#E5544E` | Afbud/skyldig/fravær |
| gold | `#F2A63B` | Advarsel/afventer/guld-rang (tekst `#3A2600`) |
| info | `#3DA9FC` | MobilePay/blå hold |

### Typografi
- **Barlow** (400–700): brødtekst, labels, knapper.
- **Barlow Condensed** (700–800): overskrifter, titler, tal — VERSALER på titler.
- Uppercase-labels har bogstavafstand (.03–.1em).

### Komponent-sprog
Pille-badges, runde hjørner (kort 14–20px, knapper 11–12px, pille/avatar 999px),
bottom-sheets til opret/redigér, segment-piller til faner, initial-avatarer
(ingen fotos), skeleton-loaders, tomme tilstande med ikon+tekst, pull-to-refresh.

---

## 4. Navigation & skærme

Bund-navigation (mobil) / sidebar (bred skærm), 4–5 faner afhængigt af rolle:

### Tab 0 · Oversigt (startskærm)
- **Hold-switcher** øverst (Alle / hvert hold brugeren er på) — filtrerer alt.
- **"Næste på programmet"-hero** — næste begivenhed, hurtig tilmeld/afbud.
- **Kommende / Historik**-toggle; **Træninger / Kampe** (appen kategoriserer selv
  ud fra ordet "kamp"/"træning").
- **Begivenheds-kort:** titel, dato/tid, sted, hold-badges, fremmøde ("X/Y"),
  tilmeld (grøn) / afbud (rød), kalender-download, admin-handlinger.
- **Afstemnings-kort** vises også i feedet (inline resultat-barer).
- **Sæson-matrix** (historik, bred skærm): hvem deltog hvilke datoer.
- **Begivenheds-detalje** (tryk på et kort):
  - Faner **Deltagere / Kommentarer** (antal-badge).
  - Fremmøde-overblik (13b): Tilmeldt · Mangler svar · Afbud (foldet). Rolige
    rækker m. status-prik; staff/kaptajn kan sætte svar for andre.
  - **Afløsere/gæster** (staff tilføjer på navn, "Gæst"-badge).
  - Staff: udgiv skjult begivenhed, "Påmind alle der mangler", "Hvem mødte ikke
    op?" (→ udeblivelses-bøder), redigér, slet.
  - **Kommentar-tråd** (chat-bobler, træner-mærke).
- **Drag-and-drop board** (staff): flyt spillere mellem tilmeldt/venteliste/afbud.
- **FAB (+):** kontekstuel opret (begivenhed/afstemning).

### Tab 1 · Bødekassen
- **Podium** (top 3) + **rangliste** (flest bøder gennem tiden).
- **Hold-filter:** spiller/træner ser eget hold; admin multi-vælger; bøde-admin
  sit hold.
- **"Du skylder"-callout** m. "Betal via MobilePay".
- **Bøde-historik** (tryk på et navn): navn + hold-badge + sæson, "Skyldig nu" /
  "Betalt i alt", bøder grupperet i Ubetalt / Betalt (hvem uddelte, dato,
  begrundelse), markér betalt / slet (admin/bøde-admin).
- **FAB "Uddel bøde"** (admin + bøde-admin).

### Tab 2 · Afstemninger
- **Åbne / Afsluttede**-faner. Poll-kort m. hold-badge, "ÅBEN"/lukket, stemmefrist.
- **Afstemnings-detalje:** dato-muligheder m. checkboxes (multi-valg),
  resultat-barer, "Favorit-par pr. dato" (synergi-overblik ud fra profilernes
  faste makkere; gensidige vs. én-vejs, kun staff ser én-vejs).
- Opret via FAB. **Redigering findes ikke pt.** (kun opret + slet).

### Tab 3 · Min profil
- Profil-kort (avatar, navn, e-mail, rolle-badge).
- **Mine faste makkere** (kun holdkammerater) — bruges af synergi-rapporten.
- **Skift adgangskode** (selvbetjening).
- **Push-notifikationer** (aktivér) + **Kalender-synk** (ICS-feed-URL).

### Tab 4 · Admin (kun staff)
- Hurtig-handlinger (grid): Ny begivenhed, Ny afstemning, (admin: Lyn-bøde,
  Medlemmer).
- Sektioner (kun fuld admin i dag): **Bøder** (uddel, afventende betalinger,
  bødeforslag, bødetyper, udeblivelses-bøde-config), **Medlemmer** (Hold &
  spillere: sæt på hold, ⭐ kaptajn, ⚖️ bøde-admin, roller, redigér/slet medlem,
  grupper), **Betaling** (MobilePay-boks pr. hold + fælles).

### Login / opret / nulstil
- Segment-toggle Log ind / Opret profil (kræver klubkode). "Glemt adgangskode?"
  → nulstil-mail. Recovery-link → "Vælg nyt kodeord"-skærm.

---

## 5. Roller & rettigheder (nuværende)

Base-rolle på profilen: **admin / træner / medlem**. Oven på kan et medlem være
**kaptajn** og/eller **bøde-admin** pr. hold (flag i `group_members`).

| Område | Admin | Træner | Kaptajn (eget hold) | Bøde-admin (eget hold) | Spiller |
|---|---|---|---|---|---|
| Opret begivenhed/afstemning | ✅ | ✅ | ✅ | – | – |
| Redigér/slet begivenhed | ✅ | ✅ | ✅ | – | – |
| Slet afstemning | ✅ | ✅ | ✅ | – | – |
| Sæt fremmøde for andre / påmind | ✅ | ⚠️* | – | – | – |
| Tilføj afløser, "hvem mødte ikke op?" | ✅ | ✅ | – | – | – |
| Uddel/godkend/slet bøde | ✅ | – | – | ✅ (eget hold) | – |
| Opret bødetyper | ✅ | – | – | – | – |
| Styr hold/medlemmer/roller/MobilePay | ✅ | – | – | – | – |
| Tilmeld/afbud, stem, kommentér | ✅ | ✅ | ✅ | ✅ | ✅ |

\* Håndhæves via Postgres Row-Level Security. **Bemærk:** et par staff-knapper
er i dag kun tilladt for `admin` i databasen (fremmøde-for-andre, påmind), selvom
de vises for trænere → planlagt rettet så træner bliver næsten-admin.

**Besluttede ændringer (ikke bygget endnu):** træner → næsten-admin; kaptajn får
daglig event-styring for sit hold; bøde-admin kan lave egne bødetyper+satser;
redigering af afstemninger; gæster forbliver uden for bøder/udeblivelse.

---

## 6. Datamodel (Supabase / Postgres)

Alle tabeller har Row-Level Security. Læsning er typisk åben for indloggede;
skrivning er gated på rolle-helpers (`is_admin()`, `is_staff()`, `is_captain()`,
`is_fine_admin()`, `can_admin_fine()`, `can_manage_event()`).

- **profiles** — id, navn, email, rolle (admin/træner/medlem), makker_prio_1/2.
- **groups** — hold/grupper: id, navn, type (hold/kamp-trup/anden), farve, sort,
  mobilepay_box_id.
- **group_members** — group_id, user_id, **is_captain**, **is_fine_admin**.
- **trainings** — begivenheder: titel, beskrivelse, start_tid, slut_tid, adresse,
  max_deltagere, tilmeldings_deadline, **group_id**, **group_ids[]** (ét el. flere
  hold), **synlig_fra** (planlagt synlighed), reminder_48/24_sent_at, created_by.
- **training_participants** — training_id, user_id, status (tilmeldt/venteliste/
  afmeldt), tidsstempler.
- **training_comments** — training_id, user_id, body, created_at.
- **training_guests** — training_id, navn, added_by (afløsere uden konto).
- **polls** — titel, beskrivelse, lukket_at (stemmefrist), **group_id**, created_by.
- **poll_options** — poll_id, option_tid, beskrivelse.
- **poll_responses** — poll_option_id, user_id, svar (kan/kan ikke).
- **fines** — user_id, given_by, fine_type_id, titel, belob_oere, begrundelse,
  status (ubetalt/godkendt_betalt), approved_by, paid_at. (titel/beløb udfyldes
  af en snapshot-trigger ud fra bødetypen.)
- **fine_types** — titel, belob_oere, aktiv (false = forslag afventer admin).
- **fine_leaderboard** (view) — aggregeret highscore + skyldigt pr. spiller.
- **club_config** (én række) — mobilepay_box_id (fælles), noshow_fine_type_id,
  noshow_auto_enabled.
- **notifications** — recipient_id, kind, titel, body, data, created_at.

**RPC'er / automatik:**
- `register_for_training` — tilmeld m. venteliste-logik.
- `late_cancel_training` — afbud efter frist + evt. automatisk udeblivelses-bøde.
- `send_training_reminders` — manuel "påmind alle der mangler" (hold-bevidst).
- `send_due_reminders` — **pg_cron hvert 15. min**: auto-rykker 48t + 24t før frist
  til hold-medlemmer der mangler svar.
- `admin_delete_member` — hard-delete af medlem (cascade).

---

## 7. Nøgle-funktioner (kort)

- Hold-opdeling af alt (aktiviteter, afstemninger, bødekasse, makkere).
- Serie-oprettelse af træninger (ugentlig gentagelse).
- Planlagt synlighed ("vis for spillere 1 uge før") + "Udgiv nu"-override.
- Relativ tilmeldingsfrist (X dage før hver begivenhed).
- Automatiske rykkere (48t/24t) via cron → in-app klokke.
- Automatisk udeblivelses-bøde (sent afbud + "hvem mødte ikke op?").
- Afløsere/gæster (tæller med i tilmeldt, aldrig i bøder).
- Kommentarer pr. begivenhed.
- MobilePay pr. hold (egen boks) med fælles fallback.
- Synergi/favorit-par-overblik til kampopstilling.
- Kalender-abonnement (ICS-feed pr. bruger).

---

## 8. Kendte begrænsninger / opmærksomhedspunkter

- **iOS web-push er upålideligt** → notifikationer leveres primært i in-app
  klokken, ikke som ægte push. Ægte push kræver App Store/Play-app.
- **Afstemninger kan ikke redigeres** (kun opret/slet) — planlagt.
- **Bødetyper er klub-brede** i dag (ikke pr. hold) — planlagt ændret.
- **Swipe-tilbage på iOS** kan give hvid skærm i undermenuer (kendt, ikke løst).
- Design-referencer for tidligere runder ligger i `design_handoff_*`-pakker
  (HTML-prototyper + README).

---

## 9. Sådan bruges dette dokument

Til at briefe en designer/AI om appens nuværende tilstand før optimeringer eller
nye funktioner. Prototyper leveres typisk som selvstændige HTML-filer (mørkt
terracotta-tema, samme tokens som §3); de genskabes bagefter i Flutter med
appens eksisterende komponenter — HTML kopieres ikke 1:1.
