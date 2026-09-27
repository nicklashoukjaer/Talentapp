# Automation-bro — Bookli og RankedIn

Headless robot der booker baner i Bookli og skubber data til RankedIn.
Kører **adskilt fra Flutter-appen** og udrulles ikke sammen med den.

> **Status: fase 1 — fundament.** Køer, datamodel og arbejdsgang står.
> Selve klikkene i Bookli og RankedIn er ikke skrevet. Driverne kaster en
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
| `src/bookli.js` | Playwright-driver — **fase 2** |
| `src/rankedin.js` | Playwright-driver — **fase 2** |
| `src/index.js` | Løkken |

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
