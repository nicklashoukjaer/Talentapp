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

Selektorerne er **aflæst fra de kørende sider**, ikke gættet:

| | Bookli | RankedIn |
|---|---|---|
| Login-adresse | `/sign-in` | `/en/account/login` (`/da/login` giver 404) |
| Brugerfelt | `#signin-email` | `input[name=UserName]` |
| Kodefelt | `#signin-password` | `input[name=Password]` |
| Afprøvet | ✅ accepteret | ✅ logger ind |

**Bookli er blokeret af et lokationsvalg.** Kontoen har ingen standard-
lokation, og Bookli slipper ikke videre før der er valgt en. Robotten
vælger den ikke selv: det er en varig ændring på brugerens konto, og den
kan ikke gætte hvilken klub der er den rigtige. Vælg lokationen én gang
manuelt, så kan resten skrives.

**RankedIn mangler en holdadresse.** `hentKampe` tager stien udefra, fx
`/da/team/12345`. RankedIn har ingen offentlig grænseflade, og holdets id
kender vi ikke på forhånd.

## Broen

```bash
npm run bro          # lytter på 127.0.0.1:8787
npm run test:login   # afprøver begge logins
```

Kun `127.0.0.1`, og bag `x-bridge-token` fra `.env`. Robotten har klubbens
logins og en service-nøgle der går uden om row level security — den må
hverken kunne nås udefra eller af en tilfældig proces på maskinen.

| Rute | Gør |
|---|---|
| `GET /status` | Er broen i live, og er der logins |
| `POST /bookli/valider` | Sammenholder hjemmekampe med Bookli |
| `POST /rankedin/kampe` | Henter kampoversigt fra en RankedIn-side |

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
