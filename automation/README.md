# Automation-bro — Bookli og RankedIn

Headless robot der booker baner i Bookli og skubber data til RankedIn.
Kører **adskilt fra Flutter-appen** og udrulles ikke sammen med den.

> **Status: fase 2.** Login til begge tjenester er skrevet mod de faktiske
> sider og afprøvet. RankedIn logger ind og læser. Bookli accepterer
> kodeordet, men kontoen mangler en standard-lokation — se herunder.
> Det der endnu ikke er set, er heller ikke skrevet: driverne kaster en
> tydelig fejl frem for at lade som om de har booket noget.

## Hvorfor sådan her

**Ingen booking uden et menneske.** En booking koster penge og optager en
bane. Robotten rører kun poster der står som `godkendt` — den opretter
aldrig selv noget. Afsnittet der finder afstemte datoer *rapporterer* dem,
og det er alt.

**Browserstyring, ikke API.** Hverken Bookli eller RankedIn har en offentlig
grænseflade, så det bliver Playwright. Derfor skal klikkene skrives mod de
rigtige sider i fase 2 — et gæt ville fejle stille.

**Service-nøglen bliver her.** Den går uden om row level security og må kun
findes på den maskine der kører robotten. Aldrig i Flutter-appen, aldrig i
git. `.env` er i `.gitignore`.

## Kom i gang

```bash
cd automation
npm install
cp .env.example .env     # udfyld nøgle og logins
npm run worker:dry       # læser køen, rører ingenting
```

| Kommando | Hvad den gør |
|---|---|
| `npm run worker:dry` | Læser køen og rapporterer. Ændrer intet. |
| `npm run worker:once` | Tømmer køen én gang. |
| `npm run worker` | Kører videre med fast interval. |

## Sådan hænger det sammen

```
afstemning lukkes
   └── afstemninger_klar_til_booking   (opslag: datoer med >=4 ja og ingen booking)
          └── et menneske godkender  ->  pending_bookings.status = 'godkendt'
                 └── robotten booker i Bookli   -> 'booket' + ekstern_ref
                        └── rankedin_sync       -> skubbes til RankedIn
```

## Filer

| Fil | Ansvar |
|---|---|
| `src/config.js` | Læser `.env`, ingen hemmeligheder i koden |
| `src/supabase.js` | Databaseklient med service-nøglen |
| `src/queue.js` | Hent arbejde, tag det, skriv resultatet tilbage |
| `src/browser.js` | Fælles browser-opsætning |
| `src/bookli.js` | Login ✅ · banevalidering ⚠️ · booking ❌ |
| `src/rankedin.js` | Login ✅ · læsning af kampe ✅ · skrivning ❌ |
| `src/server.js` | Broen appen kalder (kun 127.0.0.1) |
| `src/test-login.js` | Afprøver begge logins |
| `src/index.js` | Løkken |

## Hvad der virker, og hvad der ikke gør

Alt herunder er **aflæst fra de kørende sider**, ikke gættet.

| | Bookli | RankedIn |
|---|---|---|
| Login | ✅ | ✅ |
| Læsning | ✅ bookinger med dato og bane | ✅ kampe, stilling, pulje, sæson |
| Skrivning | ❌ booking ikke skrevet | ❌ kampflytning ikke skrevet |

**Banevalidering virker og er bevist begge veje.** Dagens hjemmekamp mod
Frejlev Padel 3 gav `BOOKET` med banerne D4, D11 og D12; de seks
kommende hjemmekampe gav `MANGLER_BANE`. En validator der kun kunne sige
"mangler" ville se ens ud udefra, så den positive prøve er den vigtige.

**Bookli læses gennem klubbens GraphQL-API**, ikke ved at skrabe tekst.
Kortene i kalenderen viser kun klokkeslæt — ikke dato eller år — mens
API'en giver præcise tidsstempler og banenavne.

**Booking er bevidst ikke skrevet.** En booking optager en rigtig bane og
trækker point på kontoen. Den flade har jeg ikke haft foran mig, og den
slags skrives ikke på formodning og afprøves ikke "lige for at se".
Valideringen dækker det meste af behovet: den siger hvilke kampe der
mangler baner, så et menneske kan booke dem.

**Kampflytning på RankedIn er heller ikke skrevet.** Admin-fladen skal ses
først — et gæt kunne ramme den forkerte kamp.

### To ting der kostede tid, og som er værd at kende

**RankedIns cookie-boks ligger OVEN PÅ siden.** Uden at lukke den rammer
klik ved siden af, og brødteksten bliver samtykke-tekst i stedet for
indhold. `lukSamtykke()` kaldes derfor før alt andet.

**De to faner på RankedIn er ikke bygget ens.** Standings er en rigtig
`<table>`; Matches er `div.match-row`. En selektor der virker på den ene
finder ingenting på den anden.

## Sådan ser appen bane-status

1. Byg appen én gang: `flutter build web --wasm --release`
2. Start broen: `npm run bro`
3. Åbn **http://127.0.0.1:8787/app** — appen serveres af broen selv
4. **Admin → Automations-bro** → indsæt `BRIDGE_TOKEN` fra `.env`
5. Åbn Dashboardet. Hver kommende hjemmekamp viser nu Booklis faktiske
   status — grønt med banenumre, eller gult "Ingen bane".

**Brug adressen ovenfor, ikke vercel-adressen.** Chrome spærrer for at et
offentligt websted rører 127.0.0.1:

> Permission was denied for this request to access the `loopback` address

CORS-hovederne er ikke nok længere — det kræver brugerens udtrykkelige
tilladelse. Serveres appen derimod af broen, er de to samme oprindelse, og
hverken CORS, blandet indhold eller loopback-spærringen findes.

**Det virker kun på den maskine der kører broen.** Broen lytter på
127.0.0.1, så telefoner og de øvrige medlemmer når den ikke. Svarer den
ikke, tegner Dashboardet som før — uden fejl og uden spinner. Appen holder
desuden to minutters pause efter et mislykket kald, så en slukket bro ikke
sender et kald afsted ved hver eneste gentegning.

Bemærk at appens eget flag (⚠️ Tjek Bookli) og broens svar er **to
forskellige ting**: flaget er hvad nogen har krydset af, broens svar er
hvad der faktisk står i Bookli. Derfor vises de ved siden af hinanden.

## Ved sæsonstart: opdatér RankedIn-linket

RankedIn giver holdet et **nyt id hver sæson**. Linket ligger derfor i
databasen på holdet, ikke i en fil — så en admin retter det i appen, og
robotten følger med af sig selv ved næste kørsel.

**Admin → Medlemmer & hold → vælg holdet → RankedIn-link.**

Indsæt adressen fra holdets side på RankedIn, fx
`https://www.rankedin.com/en/team/homepage/3281091`. Det er alt. Ingen
`.env` skal røres, og intet skal udrulles.

Nuværende sæson (Lunar Ligaen · Efterår 2026):

| Hold | Link |
|---|---|
| Talentløse 1 | `…/team/homepage/3281091` |
| Talentløse 2 | `…/team/homePage/3280677` |
| Talentløse Damer | ikke angivet — skriv den ind i appen når de ønsker det |

Robotten springer hold uden link over. Damerne kommer altså med i samme
øjeblik nogen skriver deres adresse ind — der skal ikke ændres kode.

## Broen

```bash
npm run verificer    # databaselæsning + begge logins
npm run test:db      # kan service-nøglen læse holdenes links?
npm run test:login   # virker Bookli og RankedIn?
npm run bro          # lytter på 127.0.0.1:8787
```

`test:db` er sin egen test med vilje. Det er service-nøglen der afgør om
holdene kan læses, og `test:login` rører slet ikke databasen — grønne
logins siger altså intet om den del.

Kun `127.0.0.1`, og bag `x-bridge-token` fra `.env`. Robotten har klubbens
logins og en service-nøgle der går uden om row level security — den må
hverken kunne nås udefra eller af en tilfældig proces på maskinen.

| Rute | Gør |
|---|---|
| `GET /status` | Er broen i live, og er der logins |
| `POST /bookli/valider` | `BOOKET` / `MANGLER_BANE` pr. hjemmekamp |
| `POST /bookli/book` | Booker — svarer i dag at den ikke er skrevet |
| `POST /rankedin/kampe` | Kampprogram for ét hold, eller alle med et link |
| `POST /rankedin/stilling` | Stilling, pulje og sæson pr. hold |

Fejl sendes videre **som de er**, med `status: "FEJL"` og den oprindelige
besked. En generisk "noget gik galt" ville skjule netop det der gør fejlen
brugbar — fx at Bookli venter på et lokationsvalg.

## Databasen

| Tabel | Indhold |
|---|---|
| `pending_bookings` | Køen over banebookinger. `afventer → godkendt → i_gang → booket`, eller `afvist`/`fejlet`. |
| `rankedin_sync` | Hvad der mangler at blive skubbet til RankedIn. |
| `afstemninger_klar_til_booking` | Opslag: afsluttede afstemninger hvis datoer mangler en booking. |

To ting værd at kende:

**`forsoeg` tælles op ved hvert forsøg.** Når `MAX_FORSOEG` er nået, sættes
posten til `fejlet` i stedet for at blive lagt tilbage. En post der fejler
igen og igen skal ses af et menneske, ikke køre i ring.

**Posten låses optimistisk.** Den markeres `i_gang` med en betingelse om at
den stadig er `godkendt`. To robotter kan derfor ikke booke den samme bane
to gange.

## Migrationer

- `20260927120000_automation_bridge.sql` — tabeller, adgang, tidsstempler
- `20260927120100_afstemning_til_booking.sql` — opslaget

**Ingen af dem er kørt mod produktionen endnu.** De er afprøvet med en
transaktion der ruller sig selv tilbage, så resultatet kunne ses uden at
ændre noget.
