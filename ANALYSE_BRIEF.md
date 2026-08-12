# Analyse-brief: De Talentløse Hjørring (klub-app)

> Kopiér hele dette dokument ind i en AI-assistent og bed om analysen i afsnit 10.
> Sidst opdateret: 12. august 2026.

---

## 1. Din opgave

Du skal gennemgå en klub-app der **kører i produktion** for en lille dansk
padel/badminton-forening, og finde manglende funktioner, svagheder og
optimeringsmuligheder.

Du har ikke adgang til koden — kun denne beskrivelse. Stil spørgsmål hvis noget
er uklart frem for at gætte, og skriv tydeligt når en anbefaling bygger på en
antagelse.

## 2. Rammer du skal respektere

Det her er ikke et kommercielt produkt med et budget. Anbefalinger skal passe
til virkeligheden:

- **Én udvikler**, der bygger det ved siden af et fuldtidsjob.
- **Ca. 19 brugere** fordelt på 3 hold. Ikke 19.000.
- **Gratis/billig infrastruktur** (Supabase free/pro, Vercel hobby). Forslag der
  kræver betalt tredjeparts-SaaS skal have en meget klar begrundelse.
- **Ingen omskrivning.** Forslag om at skifte framework, sprog eller
  backend-leverandør er ikke brugbare. Arbejd inden for Flutter + Supabase.
- **Mobil-først.** Næsten al brug sker på telefon, som installeret PWA.
- Foreningen er frivilligt drevet. Funktioner der kræver meget administration
  for at give værdi, er dårlige forslag.

## 3. Hvad appen er

Medlemmer ser klubbens aktiviteter (træninger og kampe), tilmelder sig eller
melder afbud, stemmer om kampdatoer, følger en bøde-"highscore" (Bødekassen) og
styrer egen profil.

Staff (admin/træner) og hold-roller (kaptajn) administrerer klubben inde i
samme app — der er **ingen separat admin-portal**; alt er gated på rolle.

Klubben har flere hold (Talentløse 1, Talentløse 2, Talentløse Damer). Næsten
alt indhold kan knyttes til ét eller flere hold.

## 4. Teknik

- **Flutter web**, bygget med `--wasm`, udrullet som PWA.
- **Hosting:** GitHub Actions → Vercel. Auto-deploy ved push til `main`.
- **Backend:** Supabase — Postgres, Auth, Row-Level Security, edge functions,
  pg_cron.
- **Push:** OneSignal. iOS web-push er upålideligt, så den pålidelige kanal er
  en in-app notifikations-klokke.
- **Kodestørrelse:** ~16.200 linjer Dart i ét bibliotek. Alle skærme er
  `part of 'main.dart'`. De to største filer fylder 4.374 og 4.151 linjer.
- **Tests:** 2 testfiler. Den ene kompilerer ikke. CI kører hverken
  `flutter analyze` eller `flutter test` — den bygger og deployer direkte.
- **16 tabeller**, alle med RLS slået til og politikker på. **22 databasefunktioner.**
- **3 edge functions:** `notify` (push), `calendar-feed` (ICS-abonnement),
  `smart-responder` (kildekoden findes kun deployet, ikke i repoet).
- **2 cron-jobs**, begge hvert 15. minut: rykkere og "udgiv-nu"-notifikationer.

## 5. Datamodel (forkortet)

- **profiles** — navn, email, rolle (`admin`/`træner`/`medlem`), 2 faste
  makkere, `kalender_alle_hold`.
- **groups** — hold. Kan samles i **hold_groups** (holdgrupper), som deler
  bødekasse, bødetyper og MobilePay-boks.
- **group_members** — `group_id`, `user_id`, `is_captain`, `is_trainer`.
- **trainings** — begivenheder: titel, start/slut, adresse, max deltagere,
  tilmeldingsfrist, `group_ids[]` (ét eller flere hold), `synlig_fra`
  (planlagt synlighed), `series_id` (gentagne), `push_sent_at`.
- **training_participants** — status `tilmeldt`/`venteliste`/`afmeldt`.
- **training_comments**, **training_guests** (afløsere uden konto).
- **polls** — `group_ids[]`, type `dato`/`tekst`, `allow_multiple`, stemmefrist.
- **poll_options** — `option_tid`, `beskrivelse`, `heldags`.
- **poll_responses** — svar pr. mulighed (kan/kan ikke).
- **fines** — bøder med status ubetalt/godkendt_betalt; beløb og titel
  fastfryses via trigger ud fra bødetypen.
- **fine_types**, **fine_leaderboard** (view), **club_config**,
  **notifications**, **device_tokens**.

## 6. Roller

Base-rolle på profilen: **admin**, **træner**, **medlem**. Oven på det:
**kaptajn** pr. hold og **træner for et bestemt hold** (flag pr. medlemskab).

- **Admin** — alt.
- **Træner** — som admin, undtagen at slette medlemmer og røre MobilePay.
- **Kaptajn** — fuld styring af egne holds begivenheder, afstemninger og bøder.
- **Spiller** — tilmeld/afbud, stem, kommentér.

"Træner for et hold" er adskilt fra træner-rollen: flaget betyder at personen
ikke er spiller på dét hold. De tæller ikke i spillertallet, optager ingen
plads, får ingen rykkere, kan ikke vælges som makker og er ude af bødekassen
(indtil de får en bøde). Samme person kan være træner for ét hold og almindelig
spiller på et andet.

Alt håndhæves i Postgres RLS, ikke kun i UI'et.

## 7. Skærme og funktioner

**Oversigt (start)** — hold-filter, "næste på programmet"-hero, kommende vs.
historik, træninger vs. kampe. Begivenhedskort med tilmeld/afbud, fremmøde
"X/Y", hold-badges, kalender-download. Afstemninger vises i samme feed.
Sæson-matrix på brede skærme (hvem deltog hvornår).

**Begivenheds-detalje** — faner Deltagere/Kommentarer. Fremmøde-overblik:
Træner · Tilmeldt · Mangler svar · Afbud. Staff kan sætte svar for andre,
tilføje afløsere, udgive skjulte begivenheder, "påmind alle der mangler" og
"hvem mødte ikke op?" (→ udeblivelses-bøder). Kommentartråd.

**Bødekassen** — podium (top 3) + rangliste, hold-filter, "du skylder"-callout
med MobilePay-link, bøde-historik pr. spiller (ubetalt/betalt, hvem uddelte,
begrundelse), markér betalt.

**Afstemninger** — åbne/afsluttede. Dato-afstemninger (flere datoer kan vælges,
tid er valgfri) og tekst-afstemninger (kan låses til ét svar). Resultat-barer.
"Favorit-par pr. dato": et synergi-overblik der ud fra medlemmernes faste
makkere viser hvilken dato der giver flest spilbare par — bruges til at stille
hold til kampe.

**Min profil** — faste makkere, skift kodeord, aktivér push, kalender-abonnement
(personligt ICS-feed).

**Admin** — medlemmer og hold (sæt på hold, kaptajn, træner, roller, slet),
holdgrupper, bøde-opsætning (typer, forslag, udeblivelses-regler), MobilePay.

**Automatik** — serie-oprettelse af træninger med interval (hver 1.-4. uge),
planlagt synlighed, relativ tilmeldingsfrist, automatiske rykkere 48t og 24t før
frist, automatisk udeblivelses-bøde ved sent afbud.

## 8. Kendte huller — brug ikke tid på at genfinde dem

Disse er allerede identificeret. Nævn dem kun hvis du har en væsentligt bedre
løsning end den oplagte:

1. **Notifikationer kan ikke markeres som læst.** Læst-status ligger i
   browserens localStorage, altså pr. enhed, og forsvinder når lagringen ryddes.
   Der findes ingen UPDATE-politik på `notifications`, så appen kan ikke skrive
   status til serveren. En "markér som læst"-knap er planlagt.
2. **Ingen reel testdækning.** To testfiler, den ene kompilerer ikke, og CI
   kører dem ikke.
3. **Skema-drift.** Flere databaseobjekter er ældre end migrationsmappen og
   findes kun i produktion (bl.a. `fine_leaderboard`, flere RLS-politikker,
   `get_poll_synergy_report`). Produktionen har været foran repoet.
4. **`smart-responder`-funktionens kildekode findes ikke i repoet.**
5. **To meget store filer** (4.374 og 4.151 linjer).
6. **iOS web-push er upålideligt.** Ægte push kræver en native app.
7. **Swipe-tilbage på iOS** kan give hvid skærm i undermenuer.
8. **Afstemningers datoer kan ikke redigeres** efter oprettelse (titel,
   beskrivelse, frist og hold kan).
9. **Ingen "kopiér afstemning/begivenhed til et andet hold".** Skal man have
   samme afstemning til to hold hver for sig, skal alt indtastes igen.
10. **`APP_OVERVIEW.md` er delvist forældet** enkelte steder.

## 9. Sådan bruges appen i praksis

Sæsonen planlægges typisk ved at oprette en serie træninger måneder frem med
"vis for spillerne 1 uge før". Kampdatoer aftales via en dato-afstemning, hvor
spillerne krydser af hvilke dage de kan; derefter bruges favorit-par-overblikket
til at sætte hold. Bødekassen er en social ting — mest sjov, ikke økonomi.

Den typiske bruger åbner appen få gange om ugen på sin telefon, primært for at
svare på en tilmelding.

## 10. Det du skal levere

1. **Manglende funktioner.** Hvad ville en klub som denne have gavn af, som
   ikke findes? Tænk hele sæsonen igennem — planlægning, afvikling, opfølgning,
   fastholdelse af medlemmer, ny-medlem-onboarding, sæsonafslutning.
2. **Svagheder i det der findes.** Steder hvor modellen eller flowet knækker,
   når klubben vokser, når nogen gør noget uventet, eller når data bliver rodet.
3. **Risici.** Sikkerhed, privatliv/GDPR, datatab, drift, afhængighed af én
   person.
4. **Brugeroplevelse.** Hvor skaber appen sandsynligvis friktion for et
   almindeligt medlem der bare skal svare ja eller nej?
5. **Datamodel.** Ser noget skævt ud? Modellerer noget virkeligheden forkert?

**Format:** Prioritér efter værdi i forhold til indsats. For hvert punkt: hvad,
hvorfor det betyder noget for præcis denne klub, og hvor stort du vurderer
arbejdet er. Vær konkret frem for generel — "tilføj analytics" er ubrugeligt,
"vis hvem der aldrig har svaret på en tilmelding de sidste 3 måneder, så
kaptajnen kan ringe til dem" er brugbart.

Vær gerne kritisk. Det er mere værd at høre hvad der er galt end at få ros.
