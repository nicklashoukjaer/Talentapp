# De Talentløse Hjørring — Funktions-katalog (til design)

Komplet liste over **alle funktioner i appen** med status, så en designer/AI
hurtigt kan se hvad der allerede findes, og hvad der skal designes/bygges.

Se `APP_OVERVIEW.md` for arkitektur, datamodel og design-tokens (mørkt terracotta-
tema, Barlow). Prototyper laves som selvstændige HTML-filer i samme tokens og
genskabes bagefter i Flutter — HTML kopieres ikke 1:1.

### Status-nøgle
- ✅ **Udviklet** — færdigt og i produktion i dag.
- 🔧 **Besluttet, skal bygges** — aftalt, men ikke lavet endnu (design ønskes hvor markeret ⭐).
- 💡 **Idé** — ikke besluttet endnu.

---

## 1. Login & konto
- ✅ Log ind (e-mail + adgangskode)
- ✅ Opret profil med **klubkode** (navn, klubkode, e-mail, kode)
- ✅ "Glemt adgangskode?" → nulstil-mail
- ✅ "Vælg nyt kodeord"-skærm (via nulstil-link)
- ✅ Skift adgangskode inde fra profilen
- ✅ Installér som app på hjemmeskærm (PWA-banner)

## 2. Oversigt (startskærm)
- ✅ **Hold-switcher** — filtrér alt til Alle / et bestemt hold
- ✅ **"Næste på programmet"-hero** med hurtig tilmeld/afbud
- ✅ **Kommende / Historik**-toggle
- ✅ **Træninger / Kampe**-opdeling (auto-kategori ud fra "kamp"/"træning")
- ✅ Begivenheds-kort: titel, dato/tid, sted, **hold-badges**, fremmøde "X/Y"
- ✅ Tilmeld (grøn) / Afbud (rød) direkte fra kortet
- ✅ Tilføj til kalender (.ics-download pr. begivenhed)
- ✅ Afstemninger vist inline i feedet
- ✅ **Sæson-matrix** (historik, bred skærm): hvem deltog hvilke datoer
- ✅ Tom-/loading-/fejl-tilstande + pull-to-refresh

## 3. Opret / redigér begivenhed
- ✅ Opret begivenhed (bundsheet): titel, beskrivelse, max deltagere, sted
- ✅ Grupperet **dato + fra/til-tid** (rul-hjul + hurtig-chips)
- ✅ **Vælg ét eller flere hold** ("Hvem kan deltage?")
- ✅ **Gentag ugentligt** (serie af begivenheder)
- ✅ **Relativ tilmeldingsfrist** (X dage før hver begivenhed)
- ✅ **Planlagt synlighed** ("vis for spillere 1 uge før") + **"Udgiv nu"**-override
- ✅ Redigér begivenhed (bundsheet)
- ✅ Slet begivenhed

## 4. Begivenheds-detalje
- ✅ Faner **Deltagere / Kommentarer** (m. antal-badge)
- ✅ **Fremmøde-overblik:** Tilmeldt · Mangler svar · Afbud (foldet), status-prikker
- ✅ Staff/kaptajn: sæt tilmeld/afbud **for andre** (✓/✗)
- ✅ **"Påmind alle der mangler"**
- ✅ **Afløsere/gæster** — tilføj på navn uden konto, "Gæst"-badge, tæller med
- ✅ **"Hvem mødte ikke op?"** → uddeler udeblivelses-bøder
- ✅ **Kommentar-tråd** (chat-bobler, træner-mærke, slet egen/staff)
- ✅ **Drag-and-drop board** (flyt mellem tilmeldt/venteliste/afbud)

## 5. Afstemninger
- ✅ **Åbne / Afsluttede**-faner
- ✅ Poll-kort m. hold-badge, "ÅBEN"/lukket, stemmefrist
- ✅ Opret afstemning: titel, beskrivelse, **stemmefrist**, flere dato-muligheder
- ✅ **Vælg hold** ("Hvem kan stemme?")
- ✅ Stem (multi-valg af datoer) + resultat-barer
- ✅ **Favorit-par pr. dato** (synergi-overblik: gensidige vs. én-vejs makkere)
- ✅ Slet afstemning
- ✅ **Redigér afstemning** (titel, beskrivelse, stemmefrist, hold)
- ✅ **Type Dato eller Tekst** (svarmuligheder med %) + "tillad flere svar" (enkelt/fler-valg)

## 6. Bødekasse & bøder
- ✅ **Podium** (top 3) + rangliste (highscore)
- ✅ **Hold-filter** (spiller/træner: eget hold · admin: multi-vælg · bøde-admin: eget hold)
- ✅ **"Du skylder"-callout** + **Betal via MobilePay**
- ✅ **Bøde-historik pr. spiller:** navn + hold-badge + sæson, Skyldig/Betalt,
  Ubetalt/Betalt-grupper (hvem uddelte, dato, begrundelse)
- ✅ Uddel bøde (admin + bøde-admin)
- ✅ Markér betalt / slet bøde (admin + bøde-admin)
- ✅ **MobilePay pr. hold** (egen boks) + fælles fallback
- ✅ Bødetyper (opret/ret/slet — admin) + **medlem kan foreslå** ny type
- ✅ **Udeblivelses-bøde:** vælg bødetype + auto-opkrævning ved sent afbud
- ✅ **Holdgrupper:** saml hold der deler bødekasse/bødetyper/MobilePay (admin-skærm)
- ✅ **Bødetyper pr. fællesskab** (holdgruppe / selvstændigt hold / fælles)
- ✅ **MobilePay pr. fællesskab** + **bødekasse deles pr. holdgruppe**

## 7. Min profil
- ✅ Profil-kort (avatar, navn, e-mail, rolle-badge)
- ✅ **Mine faste makkere** (kun holdkammerater) → bruges af synergi-rapporten
- ✅ Skift adgangskode
- ✅ Aktivér push-notifikationer
- ✅ **Kalender-synk** (personlig ICS-feed-URL til Google/Apple/Outlook)

## 8. Admin / hold-styring (Admin-fane)
- ✅ Hurtig-handlinger: Ny begivenhed, Ny afstemning, Lyn-bøde, Medlemmer
- ✅ **Hold & spillere:** sæt medlemmer på hold, filtrér, "Tildel"-markering
- ✅ Udnævn **⭐ kaptajn** / **⚖️ bøde-admin** pr. hold
- ✅ Skift **roller** (admin/træner/spiller)
- ✅ Redigér medlem (navn) + **send nulstil-kodeord-mail**
- ✅ **Slet medlem** (fjernes fra alle lister; advarsel ved ubetalt gæld)
- ✅ **Grupper/hold:** opret, redigér (navn/type/farve), slet
- ✅ Afventende betalinger (godkend) + afventende bødeforslag (godkend & sæt sats)
- ✅ MobilePay-opsætning pr. hold + fælles

## 9. Notifikationer & automatik
- ✅ **In-app notifikations-klokke** (den pålidelige kanal)
- ✅ **Automatisk rykker** 48t + 24t før tilmeldingsfrist (kun dem der mangler svar)
- ✅ Push (OneSignal/web) — *bemærk: iOS web-push er upålideligt*
- ✅ **Automatisk udeblivelses-bøde** ved sent afbud (hvis slået til)

## 10. Tværgående
- ✅ Mørkt terracotta-design, Barlow (se `APP_OVERVIEW.md` §3)
- ✅ Skeleton-loaders, tomme tilstande, fejl + "prøv igen", pull-to-refresh
- ✅ Offline-venligt (cachet data vises straks)
- ✅ Responsivt: bund-nav (mobil) / sidebar (bred skærm)
- ✅ Ctrl+K kommando-palet (hurtig opret/søg)

---

## Roller & rettigheder (kort)
Base: **admin / træner / medlem**. Tillæg pr. hold: **kaptajn** (⭐).
*(Bøde-admin er fjernet — kaptajnen styrer bøderne for sit hold.)*

| | Admin | Træner | Kaptajn (egne hold) | Spiller |
|---|---|---|---|---|
| Opret/redigér/slet begivenhed & afstemning | ✅ | ✅ | ✅ | – |
| Daglig event-styring (fremmøde, påmind, afløser, udeblivelse, board) | ✅ | ✅ | ✅ | – |
| Uddel/godkend/slet bøder | ✅ | ✅ (alle) | ✅ (egne holds spillere) | – |
| Bødetyper, roller, udnævne kaptajner, opret/slet hold | ✅ | ✅ | – | – |
| **Slette medlemmer** | ✅ | ❌ | – | – |
| **MobilePay-opsætning** | ✅ | ❌ | – | – |
| Tilmeld/afbud, stem, kommentér | ✅ | ✅ | ✅ | ✅ |

Rolle + ansvarlige hold (kaptajn) sættes i **Admin → Hold & spillere → redigér medlem**.

---

## Status
Alle besluttede funktioner er nu bygget og i produktion (rolle-omlægning,
afstemnings-typer + redigering, holdgrupper med bødetyper/MobilePay/bødekasse
pr. fællesskab). Nye ønsker aftales løbende.
