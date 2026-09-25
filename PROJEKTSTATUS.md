# De Talentløse Hjørring — projektstatus

Selvstændigt overblik til en projektleder der skal ind i projektet uden
forhåndskendskab. Alle tal er trukket direkte fra produktionsdatabasen og
kodebasen **25. september 2026**.

Se også `APP_OVERVIEW.md` (arkitektur og datamodel i detaljer) og
`FEATURES.md` (funktionskatalog). Begge er delvist forældede — dette dokument
har forrang ved uenighed.

---

## 1. Hvad det er

En **PWA** til padelklubben De Talentløse Hjørring. Medlemmer ser træninger og
kampe, tilmelder sig eller melder afbud, stemmer om kampdatoer, følger en
bødekasse og styrer egen profil. Der er **ingen separat administrationsportal**
— alt foregår i samme app, afgrænset på rolle.

Appen bruges i den nordjyske **Lunar Liga**. Sæsonerne er forår (februar–juli)
og efterår (august–januar). En dato i januar hører til efteråret før.

### Omfang lige nu

| | |
|---|---|
| Medlemmer | 22 |
| Heraf med push slået til | 12 |
| Hold | 3 |
| Begivenheder | 45 (31 kommende) |
| Til-/afmeldinger registreret | 275 |
| Afstemninger | 5 med 141 svarmuligheder og 418 stemmer |
| Bøder | 33 fordelt på 12 aktive bødetyper |
| Beskeder sendt | 1.093 |

**Holdene:** Talentløse 1 (8 spillere, 1 træner), Talentløse 2 (12 spillere,
1 træner), Talentløse Damer (4 spillere, 1 træner, 1 kaptajn).

Det er en **lille, lukket klub hvor alle kender hinanden**. Det er en
forudsætning for flere designvalg — se afsnit 6.

---

## 2. Teknik

- **Flutter web**, bygget med `--wasm`. Ét Dart-bibliotek: `lib/main.dart` er
  roden, alle øvrige filer er `part of`. Cirka **20.600 linjer**.
- **Supabase**: Postgres med row level security på alle 18 tabeller,
  Auth, 2 edge functions (Deno), pg_cron.
- **Hosting**: GitHub Actions → Vercel. Push til `main` deployer automatisk.
- **Push**: OneSignal. Web-push på iOS kræver at appen ligger på hjemmeskærmen.
- **52 migrationer**, **134 commits**.

### De største filer

| Fil | Linjer | Indhold |
|---|---|---|
| `views/oversigt_view.dart` | 5.324 | Feed, begivenhedsdetalje, deltagere |
| `views/dashboard_view.dart` | 4.839 | Admin: medlemmer, hold, bødeopsætning |
| `views/bodekasse_view.dart` | 2.134 | Rangliste, takstblad, regnskab |
| `views/afstemninger_view.dart` | 2.028 | Afstemninger og stemmeoverblik |

### Baggrundsjob

To pg_cron-job kører hvert 15. minut: `send_due_reminders` (rykkere til dem
der ikke har svaret) og `send_due_event_pushes` (udsender push først når en
begivenhed bliver synlig, så otte serieoprettede træninger ikke spammer på
én gang).

---

## 3. Roller

| Rolle | Hvor | Hvad |
|---|---|---|
| **Admin** | `profiles.rolle` | Alt. Klub-bredt. |
| **Træner** | `group_members.is_trainer` | **Pr. hold.** Tæller ikke som spiller, er ikke med i bødekassen, kan ikke vælges som makker og får ikke rykkere. Kan godt være spiller på et andet hold. |
| **Kaptajn** | `group_members.is_captain` | Pr. hold. Må oprette og styre eget holds begivenheder. |
| **Medlem** | standard | Ser og svarer på eget holds indhold. |

Rettigheder håndhæves i databasen gennem `is_staff()`, `is_admin()`,
`can_manage_event()`, `can_manage_training()` og `can_admin_fine()`. UI'et
skjuler knapper, men **databasen er den der bestemmer**.

En vigtig skelnen: `is_staff()` er rollebaseret og dermed **klub-bred**.
Trænere tildeles derimod **pr. hold**. Hvor det betyder noget — fx
kommentarnotifikationer — slås trænere op i `group_members`, ikke via
`is_staff()`.

---

## 4. Hvad der er bygget

### Begivenheder
Træninger og kampe, knyttet til ét eller flere hold. Serieoprettelse med
interval (hver 1.–4. uge). Udgivelsesdato, så en hel sæson kan lægges ind
uden at holdet ser den med det samme. Tilmeldingsfrist pr. begivenhed.
Venteliste. Afløsere kan vælges blandt eksisterende medlemmer eller skrives
ind som gæster. Kommentarer. Registrering af hvilken banehalvdel hver spiller
foretrækker (venstre/højre/begge) med optælling pr. begivenhed.

### Afstemninger
Dato- og tekstafstemninger, ét eller flere hold ad gangen. Datoer kan være
heldags eller med klokkeslæt. Stemmefrist der lukker automatisk. Overblik
over hvem der har stemt hvad, og rykkere til dem der mangler. Datoer med
mindst fire stemmer kan bruges direkte når man opretter en kamp, og
markeres så automatisk som booket — og afmarkeres igen hvis kampen slettes.
Hele afstemningen kan redigeres bagefter, inklusive datoer og svarmuligheder.

### Bødekassen
Rangliste med podie. Takstblad synligt for alle. Kreditbøder med negativt
beløb (fx "stikker" på −20 kr) der modregnes, men aldrig udbetales.
"Gør op" afregner alt for en spiller i ét klik. Spillere kan foreslå
bødetyper til godkendelse. MobilePay-betaling med boks pr. hold.
Periodeopgørelse over hvad der er kommet ind — sæson, år eller egen periode.

### Notifikationer
Ti beskedtyper. Alle lander i klokken inde i appen; de fleste sendes også
som push. Beskeder er **holdbevidste**: indhold knyttet til et hold rammer
kun det holds medlemmer plus admins.

`training_oprettet`, `training_aendret`, `training_afmeldt`,
`training_tilmeldt_af_anden`, `training_rykker`, `training_svar`,
`training_kommentar`, `poll_rykker`, `boedeforslag`, `boede_selvmeldt`.

Et tryk på en besked åbner det rigtige sted i appen.

**Abonnementer:** `tilmeldings_abonnenter` styrer hvem der får besked når
nogen til- eller afmelder sig. Den er bevidst uafhængig af medlemskab, så en
admin kan følge et hold uden at være spiller på det.

### Øvrigt
Kalenderfeed pr. bruger (udelader afbud, medtager afløserroller).
Engangs-invitationslinks pr. hold, der erstattede en fælles klubkode.
Kommandopalet på Ctrl+K. PC-visning fra 1100 px med fast sidebar,
holdfilter og begivenheder i tabelform.

---

## 5. Sådan arbejdes der

Nicklas (admin og ejer) beslutter og afprøver. Al kode skrives og
vedligeholdes af Claude Code.

Arbejdsgangen der har fæstnet sig:

1. Ændringer listes punkt for punkt **inden** de bygges, og alt der rører
   fungerende kode markeres eksplicit.
2. Migrationer vises som SQL inden de køres.
3. Databaseændringer afprøves mod produktionen med en transaktion der
   **ruller sig selv tilbage**, så man ser det faktiske resultat uden at
   ændre noget. Det har fanget flere fejl inden de nåede ud.
4. Efter hver ændring: `flutter analyze`, `flutter build web --wasm`, commit,
   push. Vercel deployer automatisk.

**Der er ingen automatiserede tests.** Afprøvning sker manuelt i appen og med
rollback-forespørgsler mod databasen.

---

## 6. Designvalg en projektleder bør kende

Disse er truffet bevidst. Flere ville være forkerte i en større organisation.

**Betaling er selvangivelse.** MobilePay melder ikke tilbage til appen. Trykker
en spiller "betal", markeres bøderne som betalt i samme øjeblik — også hvis de
lukker MobilePay uden at betale. Til gengæld sættes et `selvmeldt`-flag, det
vises i gult som "ikke bekræftet", og admin får besked med det samme, så
beløbet kan tjekkes. Valgt fordi klubben er lille nok til at snyd opdages
socialt.

**Én besked pr. svar, ikke en opsamling.** Admin får op til 12
notifikationer når et hold svarer på en kamp. Det er ønsket: det er den
eneste måde at følge med i hvem der mangler.

**Trænere er ikke spillere.** De tælles ikke med i deltagerantal, er ikke i
bødekassen, får ikke rykkere og kan ikke vælges som makker — medmindre de er
tildelt et andet hold som spiller.

**Bulkændringer må ikke udløse beskeder.** Da alle kommende træningers frist
blev ændret fra 2 til 1 dag, ville triggeren have sendt omkring 135 beskeder
ud. Triggeren blev slået fra under rettelsen og til igen bagefter. Det bør
være standardfremgangsmåden ved administrative masserettelser.

---

## 7. Kendte begrænsninger

**iOS swipe-tilbage genstarter hele appen.** Swiper man tilbage fra en
begivenhed, river iOS hele webview'et ned — `sessionStorage` ryddes, og appen
henter og starter forfra over et par sekunder. Der er lagt en startskærm ind
så det ikke ligner et nedbrud, men årsagen er ikke løst, og det er uvist om
den kan løses fra appens side. Pilen i toppen virker korrekt og øjeblikkeligt.

**10 af 22 mangler push.** Herunder træneren Stine, som er træner på alle tre
hold. Push kan ikke slås til for folk — browseren kræver at de selv trykker
ja. Der er et banner i Oversigt, som har fordoblet tilslutningen fra 5 til 12.

**Invitationslinks udløber aldrig**, og der er ingen liste over udestående
links. Et link sendt for et år siden virker stadig, hvis ingen har brugt det,
og det kan ikke trækkes tilbage.

**Sletning af en gæst sker uden bekræftelse** (`oversigt_view.dart`,
`_deleteGuest`). Det er den eneste sletning i appen uden dialog foran.

**Ingen sæsonarkivering i bødekassen.** Ranglisten viser hele historikken.
Periodeopgørelsen dækker delvist behovet, men bøder nulstilles aldrig.

**Ingen tests.** Se afsnit 5.

---

## 8. Drøftet, ikke bygget

- Sæsonarkivering af bødekassen
- Påmindelse til spillere der mangler at angive makker eller banehalvdel
- Venstre/højre-mærker i afstemningernes stemmelister
- Udløbsdato på invitationslinks og en oversigt over udestående links
- At forhindre at iOS' swipe genstarter appen

---

## 9. Ordliste

| Ord | Betyder |
|---|---|
| Bødekassen | Klubbens bødesystem med rangliste |
| Takstblad | Oversigt over bødetyper og beløb |
| Stikker | Kreditbøde med negativt beløb der modregnes |
| Gør op | Afregn alt udestående for én spiller |
| Makker | Fast spillepartner |
| Afløser | Indhopper på en begivenhed |
| Heldags | Afstemningsdato uden klokkeslæt |
| Booket | Dato hvor der er oprettet en kamp |
