// Bookli-driver.
//
// Selektorerne herunder er AFLÆST fra den kørende side, ikke gættet:
//   #signin-email     input[type=email]  name=email
//   #signin-password  input[type=password] name=password
//   button[type=submit] med teksten "Log ind"
//
// Bookli er en JavaScript-app bag Cloudflare; siden kan ikke hentes med et
// almindeligt HTTP-kald, derfor en rigtig browser.
import { config } from './config.js';

/// Logger ind. Kaster med en læsbar besked hvis det ikke lykkes.
export async function logInd(side) {
  await side.goto(config.bookli.loginUrl, {
    waitUntil: 'networkidle',
    timeout: 45000,
  });
  await side.fill('#signin-email', config.bookli.email);
  await side.fill('#signin-password', config.bookli.kode);
  // Enter frem for et klik: knappens tekst afhænger af sprogvalget.
  await side.press('#signin-password', 'Enter');
  await side.waitForTimeout(5000);

  const tekst = await side.innerText('body').catch(() => '');

  // Rækkefølgen betyder noget. Bookli er en enkeltside-app, og login-
  // formularen bliver liggende SYNLIG bag lokationsvælgeren. Både
  // "er feltet der endnu" og "står der velkommen-tekst" giver derfor
  // falsk alarm. Lokationsskærmen er derimod et entydigt tegn på at
  // login LYKKEDES — så den afgøres først.
  if (/standard lokation|default location/i.test(tekst)) {
    const valgt = await vaelgLokation(side, config.bookli.lokation);
    if (!valgt) {
      throw new Error(
        `Fandt ikke "${config.bookli.lokation}" på Booklis lokationsliste. ` +
        'Login virker. Vælg lokationen én gang manuelt i Bookli, så er ' +
        'kontoen sat op og robotten kommer videre herefter.');
    }
    return true;
  }

  if (/Velkommen tilbage|Log ind på din konto/i.test(tekst)) {
    throw new Error('Bookli-login afvist — tjek BOOKLI_EMAIL og BOOKLI_PASSWORD');
  }

  return true;
}

/// Vælger klubbens lokation på Booklis lokationsskærm.
///
/// Det er en varig ændring på kontoen, så den sker KUN når Bookli selv
/// beder om det — ikke som en rutine ved hvert login.
async function vaelgLokation(side, navn) {
  // Stederne ligger foldet ind under landet. Fold Danmark ud først —
  // ellers er "Padel Club Hjørring" slet ikke i DOM'en at finde.
  const land = side.locator('text=Danmark').first();
  if (await land.count()) {
    await land.click().catch(() => {});
    await side.waitForTimeout(2500);
  }
  // Søgefeltet findes ikke altid; er der en liste, klikkes der direkte.
  const soeg = side.locator('input[type=search], input[placeholder*="øg" i]').first();
  if (await soeg.count()) {
    await soeg.fill(navn).catch(() => {});
    await side.waitForTimeout(1500);
  }
  const punkt = side.locator(`text=${navn}`).first();
  if (!(await punkt.count())) return false;
  await punkt.click().catch(() => {});
  await side.waitForTimeout(3000);
  // Nogle flader kræver en bekræftelse.
  const ok = side.locator(
    'button:has-text("Vælg"), button:has-text("Fortsæt"), button:has-text("Gem")').first();
  if (await ok.count()) {
    await ok.click().catch(() => {});
    await side.waitForTimeout(2500);
  }
  const tekst = await side.innerText('body').catch(() => '');
  return !/standard lokation|default location/i.test(tekst);
}

/// Henter brugerens bookinger i et VALGFRIT datointerval.
///
/// Læser Booklis egen GraphQL-API frem for at skrabe teksten. Kortene i
/// kalenderen viser hverken dato eller år — kun klokkeslæt — mens API'en
/// giver præcise tidsstempler og banens navn.
///
/// Kalendersiden spørger kun om DEN MÅNED man står i. Derfor er det ikke
/// nok at åbne siden og lytte med: en kamp om halvanden måned er aldrig
/// med i svaret, og så ligner en booket bane en manglende. I stedet
/// opsnappes Booklis egen forespørgsel én gang og gentages med vores
/// eget interval — måned for måned, som fladen selv gør det.
export async function hentBookinger(side, fra, til) {
  const fundne = new Map();
  let skabelon = null;       // listeforespørgslen, som den ser ud i dag
  let kortSkabelon = null;   // enkeltkortet, der kender banenavnet

  const saml = (o) => {
    if (!o || typeof o !== 'object') return;
    if (o.__typename === 'ResourceBooking' && o.startDate) {
      const id = o.id ?? `${o.startDate}-${o.resource?.name ?? ''}`;
      const foer = fundne.get(id);
      const frisk = {
        id: o.id ?? null,
        start: o.startDate,
        slut: o.endDate ?? null,
        bane: (o.resource?.name ?? '').replace(/^\[|\].*$/g, '').trim() || null,
        baneFuld: o.resource?.name ?? null,
      };
      // Kortformen kommer efter listeformen og ved mere. Behold det
      // bedste af hver, så et senere tyndt svar ikke sletter banenavnet.
      fundne.set(id, foer
          ? { ...foer,
              slut: frisk.slut ?? foer.slut,
              bane: frisk.bane ?? foer.bane,
              baneFuld: frisk.baneFuld ?? foer.baneFuld }
          : frisk);
    }
    for (const v of Object.values(o)) {
      if (Array.isArray(v)) v.forEach(saml);
      else if (v && typeof v === 'object') saml(v);
    }
  };

  const lytSvar = async (svar) => {
    if (!/\/graphql/.test(svar.url())) return;
    let data;
    try { data = await svar.json(); } catch { return; }
    for (const d of Array.isArray(data) ? data : [data]) saml(d?.data);
  };

  const lytKald = (req) => {
    if (!/\/graphql/.test(req.url())) return;
    let krop;
    try { krop = JSON.parse(req.postData() || ''); } catch { return; }
    const navne = (Array.isArray(krop) ? krop : [krop]).map((x) => x?.operationName);
    const gem = { url: req.url(), headers: req.headers(), krop };
    if (navne.includes('GetBookingsForUserCalendar')) skabelon = gem;
    if (navne.includes('GetResourceBookingCard') && !kortSkabelon) kortSkabelon = gem;
  };

  side.on('request', lytKald);
  side.on('response', lytSvar);
  try {
    await side.goto('https://bookli.app/u/calendar',
      { waitUntil: 'networkidle', timeout: 45000 });
    await side.waitForTimeout(5000);
  } finally {
    side.off('request', lytKald);
    side.off('response', lytSvar);
  }

  if (/sign-in/.test(side.url())) {
    throw new Error('Bookli sendte tilbage til login — er lokationen valgt?');
  }

  // Intet interval ønsket: det kalenderen selv hentede er svaret.
  if (!fra || !til) return sorteret(fundne);

  if (!skabelon) {
    throw new Error(
      'Fandt ikke Booklis kalender-forespørgsel (GetBookingsForUserCalendar). ' +
      'Bookli har sandsynligvis ændret sin API — banetjekket kan ikke se ' +
      'længere frem end indeværende måned før driveren er rettet.');
  }

  for (const [mFra, mTil] of maaneder(fra, til)) {
    for (const d of await send(side, skabelon, medDatoer(skabelon.krop, mFra, mTil))) {
      saml(d?.data);
    }
  }

  // Listeformen oplyser hverken sluttid eller banenavn — det gør kun
  // enkeltkortet. Hent det for de bookinger der mangler navnet, så
  // "BOOKET" kan vise HVILKE baner og ikke bare et flueben.
  if (kortSkabelon) {
    for (const b of [...fundne.values()]) {
      if (!b.id || b.bane) continue;
      const t = new Date(b.start).getTime();
      if (t < fra.getTime() || t > til.getTime()) continue;
      const krop = medKortId(kortSkabelon.krop, b.id);
      if (!krop) break;
      try {
        for (const d of await send(side, kortSkabelon, krop)) saml(d?.data);
      } catch { /* ét kort der fejler må ikke vælte hele tjekket */ }
    }
  }

  return sorteret(fundne);
}

function sorteret(m) {
  return [...m.values()].sort((a, b) => a.start.localeCompare(b.start));
}

/// Gentager et opsnappet GraphQL-kald med vores egen krop.
///
/// Kører gennem sidens egen kontekst, så cookies og Cloudflare-klarering
/// følger med — et frisk HTTP-kald udefra ville blive afvist.
async function send(side, skabelon, krop) {
  const headers = {};
  for (const [k, v] of Object.entries(skabelon.headers)) {
    // Længde, vært og komprimering sættes af klienten selv; genbrugt fra
    // en gammel forespørgsel passer de ikke til den nye krop.
    if (/^(content-length|host|:|accept-encoding)/i.test(k)) continue;
    headers[k] = v;
  }
  headers['content-type'] = 'application/json';
  const svar = await side.context().request.post(skabelon.url, {
    headers,
    data: JSON.stringify(krop),
    timeout: 45000,
  });
  if (!svar.ok()) {
    throw new Error(`Bookli svarede ${svar.status()} på kalender-opslaget`);
  }
  const data = await svar.json();
  return Array.isArray(data) ? data : [data];
}

/// Sætter datointervallet ind i listeforespørgslen, uanset om Bookli
/// sender den alene eller i en bunke.
function medDatoer(krop, fra, til) {
  const en = (x) => {
    if (x?.operationName !== 'GetBookingsForUserCalendar') return x;
    return {
      ...x,
      variables: {
        ...x.variables,
        filtering: {
          ...(x.variables?.filtering ?? {}),
          startDate: fra.toISOString(),
          endDate: til.toISOString(),
        },
      },
    };
  };
  return Array.isArray(krop) ? krop.map(en) : en(krop);
}

function medKortId(krop, id) {
  const en = (x) => x?.operationName === 'GetResourceBookingCard'
      ? { ...x, variables: { ...x.variables, id } }
      : x;
  const ud = Array.isArray(krop) ? krop.map(en) : en(krop);
  return (Array.isArray(ud) ? ud : [ud]).some((x) => x?.variables?.id === id)
      ? ud : null;
}

/// Deler et interval op i hele måneder — samme snit som Booklis egen
/// kalender bruger, så forespørgslen ligner en almindelig bladring.
function maaneder(fra, til) {
  const ud = [];
  const d = new Date(fra.getFullYear(), fra.getMonth(), 1);
  const slut = new Date(til.getFullYear(), til.getMonth(), 1);
  while (d <= slut && ud.length < 18) {
    ud.push([
      new Date(d.getFullYear(), d.getMonth(), 1, 0, 0, 0),
      new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999),
    ]);
    d.setMonth(d.getMonth() + 1);
  }
  return ud;
}

/// Sammenholder klubbens hjemmekampe med det der faktisk er booket.
///
/// Spørgsmålet er ikke "findes der en booking der rører kampen", men
/// "er HELE kampens tidsrum dækket". Forskellen er ikke teoretisk: den
/// 13. november 2026 lå to hjemmekampe (16.30–19.30 og 19.00–22.00) oven
/// på én booking 18.00–21.00, og med overlap-reglen blev de begge meldt
/// booket — selv om den første manglede bane de første halvanden time og
/// den anden den sidste time.
///
/// Tre svar:
///   BOOKET          hele kampen er dækket
///   DELVIS_BOOKET   der er baner, men ikke i hele tidsrummet
///   MANGLER_BANE    ingen booking rører kampen
///
/// `mangler` angiver de huller der ikke er dækket, så beskeden kan sige
/// præcis hvilken tid der skal bookes til.
///
/// Antallet af baner efterprøves IKKE. Bookli oplyser ikke hvor mange
/// baner en kamp kræver, og et gæt ville give falsk alarm på hver eneste
/// kamp. Kun tiden kontrolleres.
///
/// @returns {Array<{kamp, status, baner: string[], mangler: Array<{fra,til}>}>}
export async function validerBaner(side, hjemmekampe) {
  // Spørg om præcis de måneder kampene ligger i — med en dag i hver ende,
  // så en kamp den 1. eller den 31. ikke falder uden for vinduet.
  const tider = hjemmekampe.map((k) => new Date(k.start).getTime());
  const bookinger = tider.length
      ? await hentBookinger(side,
          new Date(Math.min(...tider) - 86400000),
          new Date(Math.max(...tider) + 86400000))
      : await hentBookinger(side);

  return hjemmekampe.map((k) => {
    const start = new Date(k.start).getTime();
    const slut = k.slut
        ? new Date(k.slut).getTime()
        : start + 2 * 60 * 60 * 1000;

    // Bookinger uden sluttid kan ikke tidsprøves. Bookli giver kun
    // starttid i listeformen; sluttiden følger med enkeltkortet, og det
    // hentes kun for bookinger i det vindue vi spørger om.
    let usikker = false;

    const traef = bookinger.filter((b) => {
      const bs = new Date(b.start).getTime();
      if (b.slut) return bs < slut && new Date(b.slut).getTime() > start;
      // Samme skøn som før: starter den inden for kampens vindue plus tre
      // timer, tæller den med — hellere det end at kalde en booket bane
      // manglende.
      const naer = bs >= start - 3 * 3600000 && bs <= slut + 3 * 3600000;
      if (naer) usikker = true;
      return naer;
    });

    if (!traef.length) {
      return {
        kamp: k,
        status: 'MANGLER_BANE',
        banetid: null,
        kamptid: {
          fra: new Date(start).toISOString(),
          til: new Date(slut).toISOString(),
        },
        baner: [],
        baneNavnKendt: false,
        mangler: [{ fra: new Date(start).toISOString(),
                    til: new Date(slut).toISOString() }],
        usikker: false,
        bookinger: [],
      };
    }

    // Hvornår banerne FAKTISK står reserveret. Uden det kan appen kun
    // sige at noget mangler, ikke hvad der står i Bookli — og så ved
    // holdlederen stadig ikke om det er kampen eller bookingen der er
    // sat forkert.
    const bStart = Math.min(...traef.map((b) => new Date(b.start).getTime()));
    const bSlut = traef.every((b) => b.slut)
        ? Math.max(...traef.map((b) => new Date(b.slut).getTime()))
        : null;

    const svar = {
      kamp: k,
      banetid: {
        fra: new Date(bStart).toISOString(),
        til: bSlut == null ? null : new Date(bSlut).toISOString(),
      },
      kamptid: {
        fra: new Date(start).toISOString(),
        til: new Date(slut).toISOString(),
      },
      baner: traef.map((b) => b.bane).filter(Boolean),
      // Tom liste betyder ikke "ingen bane" — kun at Bookli ikke oplyste
      // navnet i listeformen.
      baneNavnKendt: traef.some((b) => b.bane),
      usikker,
      bookinger: traef,
    };

    // Mangler bare én af bookingerne sin sluttid, kan dækningen ikke
    // regnes ud. Så meldes BOOKET som hidtil frem for at råbe vagt i
    // gevær på et ufuldstændigt grundlag — men `usikker` siger hvorfor.
    if (usikker) {
      return { ...svar, status: 'BOOKET', mangler: [] };
    }

    const huller = huln(start, slut, traef.map((b) => [
      new Date(b.start).getTime(), new Date(b.slut).getTime()]));

    return {
      ...svar,
      status: huller.length ? 'DELVIS_BOOKET' : 'BOOKET',
      mangler: huller.map(([f, t]) => ({
        fra: new Date(f).toISOString(),
        til: new Date(t).toISOString(),
      })),
    };
  });
}

/// De stykker af [fra, til] som ingen af [intervaller] dækker.
///
/// Bookinger på hver sin bane ligger oven på hinanden i tid; de lægges
/// derfor sammen til ét dækket område før hullerne findes. Ellers ville
/// tre samtidige baner give to falske huller.
///
/// Stumper under fem minutter regnes ikke med. Bookli-tider ligger på
/// hele kvarter, og et kvarters afrunding i kampens tidsrum skal ikke
/// udløse en advarsel.
function huln(fra, til, intervaller) {
  const STOEJ = 5 * 60 * 1000;

  const klippet = intervaller
      .map(([a, b]) => [Math.max(a, fra), Math.min(b, til)])
      .filter(([a, b]) => b > a)
      .sort((x, y) => x[0] - y[0]);

  const samlet = [];
  for (const [a, b] of klippet) {
    const sidste = samlet[samlet.length - 1];
    if (sidste && a <= sidste[1]) sidste[1] = Math.max(sidste[1], b);
    else samlet.push([a, b]);
  }

  const huller = [];
  let p = fra;
  for (const [a, b] of samlet) {
    if (a - p > STOEJ) huller.push([p, a]);
    p = Math.max(p, b);
  }
  if (til - p > STOEJ) huller.push([p, til]);
  return huller;
}

// ─────────────────────────────────────────────────────────────────────────
// Ledighed og ombooking
//
// Alt herunder er aflæst fra Booklis egen klient, ikke gættet:
//
//   query GetResourcesAvailableTimeSchema($resourceType,$location,$date,
//                                         $durationMinuts)
//   query GetResourceBookingIsValid($resource,$startDate,$endDate)
//   mutation ResourceBookingCancel($id,$refundPayment)
//
// Lokationen og banehallerne er klubbens egne id'er, hentet fra
// GetResourceTypes på den kørende side.
// ─────────────────────────────────────────────────────────────────────────

const LOKATION = 'ckhxfvckh178623qip9zccbebc6';   // Padel Club Hjørring

const Q_SKEMA = `query($t:ID!,$l:ID!,$d:DateTime!,$m:Int!){
  resourcesAvailableTimeSchema(resourceType:$t,location:$l,date:$d,durationMinuts:$m){
    times{ startDate endDate availableForBooking availableResources{ id name } }
  }
}`;

const Q_TYPER = `query($c:ID!,$l:ID!){
  resourceTypes(filtering:{resourceCategory:$c,location:$l}){ data{ id name } }
}`;

const Q_LEDIG = `query($r:ID!,$s:DateTime!,$e:DateTime!){
  resourceBookingIsValid(resource:$r,startDate:$s,endDate:$e)
}`;

/// Åbner bookingfladen og giver en genbrugelig GraphQL-kanal.
///
/// Kaldene skal gå gennem sidens egen kontekst: Bookli ligger bag
/// Cloudflare, og et friskt HTTP-kald udefra bliver afvist.
async function graf(side) {
  if (side.__graf) return side.__graf;
  let skabelon = null;
  const lyt = (req) => {
    if (!/\/graphql/.test(req.url()) || skabelon) return;
    try {
      const krop = JSON.parse(req.postData() || '');
      if ([].concat(krop)[0]?.operationName) {
        skabelon = { url: req.url(), headers: req.headers(), krop };
      }
    } catch { /* ikke JSON — ikke det kald vi leder efter */ }
  };
  side.on('request', lyt);
  try {
    await side.goto('https://bookli.app/u/booking/create',
      { waitUntil: 'networkidle', timeout: 45000 });
    await side.waitForTimeout(4000);
  } finally {
    side.off('request', lyt);
  }
  if (!skabelon) {
    throw new Error('Fandt ikke Booklis GraphQL-kald — er login gået igennem?');
  }
  side.__graf = async (doc, variables) => {
    const [svar] = await send(side, skabelon, { query: doc, variables });
    if (svar?.errors?.length) {
      throw new Error('Bookli: ' + svar.errors[0].message);
    }
    return svar?.data;
  };
  return side.__graf;
}

/// Alle baner klubben kan bookes på, med Booklis id.
///
/// Ledighedsskemaet er den eneste flade der oplyser banerne med id, så
/// der spørges på et par fremtidige datoer og svarene lægges sammen —
/// en bane der er optaget hele den ene dag dukker op på den anden.
export async function hentBaner(side) {
  const g = await graf(side);
  const kat = await g(`query{ resourceCategories{ data{ id name } } }`, {})
      .catch(() => null);
  const katId = kat?.resourceCategories?.data?.[0]?.id;

  const typer = katId
      ? (await g(Q_TYPER, { c: katId, l: LOKATION }))?.resourceTypes?.data ?? []
      : [];
  if (!typer.length) {
    throw new Error('Bookli oplyste ingen banehaller for lokationen.');
  }

  const fundne = new Map();
  const datoer = [14, 28, 42].map((d) => {
    const x = new Date();
    x.setDate(x.getDate() + d);
    x.setHours(12, 0, 0, 0);
    return x.toISOString();
  });

  for (const t of typer) {
    for (const d of datoer) {
      const j = await g(Q_SKEMA, { t: t.id, l: LOKATION, d, m: 60 })
          .catch(() => null);
      for (const tid of j?.resourcesAvailableTimeSchema?.times ?? []) {
        for (const r of tid.availableResources ?? []) {
          // "[D10] Sparekassen Danmark" → kortnavnet er det brugeren kender.
          const kort = (r.name.match(/^\[([^\]]+)\]/) || [])[1] || r.name;
          if (!fundne.has(kort)) {
            fundne.set(kort, {
              navn: kort,
              fuldtNavn: r.name,
              id: r.id,
              hal: t.name,
              halId: t.id,
            });
          }
        }
      }
    }
  }
  return [...fundne.values()].sort((a, b) =>
      a.navn.localeCompare(b.navn, 'da', { numeric: true }));
}

/// Er banen fri i hele [start, slut]? Booklis eget svar, uændret.
async function banenErFri(g, resourceId, start, slut) {
  const j = await g(Q_LEDIG, {
    r: resourceId,
    s: new Date(start).toISOString(),
    e: new Date(slut).toISOString(),
  });
  return j?.resourceBookingIsValid === true;
}

/// Kan VI få de ønskede baner i det nye tidsrum?
///
/// Booklis eget ledighedssvar duer ikke alene til en ombooking. Flytter
/// man en kamp fra 18–21 til 16.30–19.30, melder Bookli banerne optaget
/// i overlappet — fordi vi selv sidder på dem. Uden at tage højde for
/// det ville enhver flytning se umulig ud.
///
/// Derfor: vores egne bookinger på banen trækkes ud af det ønskede
/// tidsrum, og kun de HULLER der bliver tilbage spørges Bookli om. Er
/// der ingen huller, er banen vores i forvejen.
///
/// @returns {Array<{bane, ledig, egne, optagetAf}>}
export async function tjekLedighed(side, { baner, start, slut }) {
  const g = await graf(side);
  const alle = await hentBaner(side);
  const s = new Date(start).getTime();
  const e = new Date(slut).getTime();
  if (!(e > s)) throw new Error('Sluttid skal ligge efter starttid.');

  // Vores egne bookinger i døgnet omkring tidsrummet.
  const egne = await hentBookinger(side,
      new Date(s - 86400000), new Date(e + 86400000));

  const ud = [];
  for (const oensket of baner) {
    const bane = alle.find((b) => b.navn === oensket);
    if (!bane) {
      ud.push({
        bane: oensket,
        ledig: false,
        egne: [],
        optagetAf: 'Bookli kender ikke en bane der hedder ' + oensket,
      });
      continue;
    }

    // Vores egne stykker på præcis denne bane, klippet til tidsrummet.
    const mine = egne
        .filter((b) => b.bane === oensket && b.slut)
        .map((b) => [new Date(b.start).getTime(), new Date(b.slut).getTime()])
        .filter(([a, z]) => z > s && a < e);

    const huller = huln(s, e, mine);

    let fri = true;
    for (const [a, z] of huller) {
      // eslint-disable-next-line no-await-in-loop
      if (!(await banenErFri(g, bane.id, a, z))) { fri = false; break; }
    }

    ud.push({
      bane: oensket,
      baneId: bane.id,
      hal: bane.hal,
      ledig: fri,
      // Hvad vi selv allerede holder — så appen kan sige "du har den i
      // forvejen" frem for at love en booking der ikke skal laves.
      egne: mine.map(([a, z]) => ({
        fra: new Date(a).toISOString(),
        til: new Date(z).toISOString(),
      })),
      optagetAf: fri ? null : 'Optaget af en anden booking i Bookli',
    });
  }
  return ud;
}

/// Ombooking i kontrolleret rækkefølge.
///
/// 1. Tjek at de ønskede baner kan skaffes i det nye tidsrum, med vores
///    egne bookinger trukket fra.
/// 2. Afbestil de gamle bookinger.
/// 3. Book de ønskede baner i det nye tidsrum.
/// 4. Meld tilbage.
///
/// Trin 1 er bygget og afprøvet. Trin 2 og 3 stopper med en forklaring:
/// se `bookBane` og `afbestil` herunder. Rækkefølgen ligger her, så den
/// ikke skal opfindes igen når de to trin kan skrives — og så et
/// tørløb kan bruges i dag.
///
/// @param {{baner:string[], start, slut, gamleBookingIds?:string[],
///          bekraeft?:boolean}} plan
export async function ombook(side, plan) {
  const { baner = [], start, slut, gamleBookingIds = [], bekraeft } = plan;
  if (!baner.length) throw new Error('Ingen baner valgt.');

  // ── 1. Ledighed ────────────────────────────────────────────────────
  const ledighed = await tjekLedighed(side, { baner, start, slut });
  const mangler = ledighed.filter((b) => !b.ledig);

  const svar = {
    trin: 'LEDIGHED',
    ledighed,
    kanBookes: mangler.length === 0,
    start,
    slut,
  };

  if (mangler.length) {
    return { ...svar, status: 'OPTAGET',
      besked: 'Kan ikke ombookes: ' +
        mangler.map((b) => `${b.bane} (${b.optagetAf})`).join(', ') };
  }

  // Uden udtrykkelig bekræftelse skrives der ingenting. En ombooking
  // afbestiller rigtige baner og optager nye — det sker ikke som en
  // bivirkning af et opslag.
  if (!bekraeft) {
    return { ...svar, status: 'KLAR',
      besked: `${baner.join(', ')} kan skaffes i det nye tidsrum. ` +
        'Send bekraeft=true for at gennemføre.' };
  }

  // ── 2. Afbestil ────────────────────────────────────────────────────
  for (const id of gamleBookingIds) {
    // eslint-disable-next-line no-await-in-loop
    await afbestil(side, id);
  }

  // ── 3. Book ────────────────────────────────────────────────────────
  const nye = [];
  for (const b of ledighed) {
    // eslint-disable-next-line no-await-in-loop
    nye.push(await bookBane(side, { baneId: b.baneId, start, slut }));
  }

  return { ...svar, trin: 'BOOKET', status: 'OK', bookinger: nye };
}

/// Afbestiller en booking.
///
/// IKKE gennemført. Mutationen er fundet i Booklis klient:
///
///   mutation ResourceBookingCancel($id: ID!, $refundPayment: Boolean)
///
/// men bookingkortet i fladen viser "Kan ikke annulleres — tidsfristen
/// er overskredet", så der gælder en afbestillingsfrist vi ikke kender
/// reglerne for. En afbestilling der rammer forkert giver klubben en
/// regning og ingen bane, og den slags skrives ikke på formodning.
export async function afbestil(_side, _id) {
  throw new Error(
    'Afbestilling er ikke gennemført. Mutationen ResourceBookingCancel ' +
    'er fundet, men Bookli har en afbestillingsfrist hvis regler ikke er ' +
    'afprøvet — og en fejlramt afbestilling koster en bane og et gebyr.');
}

/// Booker baner.
///
/// IKKE gennemført, og det er ikke en forglemmelse. Booklis klient har
/// ingen almindelig "opret booking"-mutation: de eneste der findes er
/// ResourceBookingCreateCompanyReservation (klubadministratorens
/// reservation, som denne konto ikke har adgang til) og
/// ResourceBookingRecurringCreate. En spillers booking går gennem
/// betalingsfladen — kortet på en enkelt bane viste 732,00 kr fordelt
/// på fire deltagere.
///
/// En robot der gennemfører en betaling på klubbens konto uden at nogen
/// har set flowet, er ikke noget jeg skriver på formodning. Brug
/// tjekLedighed til at finde ud af HVAD der kan bookes, og book det
/// selv — det er to klik når man ved at banerne er fri.
export async function bookBane(_side, _booking) {
  throw new Error(
    'Selve bookingen er ikke gennemført. Bookli har ingen simpel ' +
    'booking-mutation for en spillerkonto — den går gennem betaling, og ' +
    'en booking koster rigtige penge. Brug /bookli/ledig til at se hvad ' +
    'der kan skaffes, og book det i Bookli.');
}
