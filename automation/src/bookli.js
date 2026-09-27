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
/// En kamp regnes som dækket hvis en booking OVERLAPPER dens tidsrum på
/// samme dag. Der kræves ikke nøjagtigt samme klokkeslæt: en kamp kl.
/// 11–14 kan sagtens have en bane booket 11–12 og en anden 12–14.
///
/// @returns {Array<{kamp, status: 'BOOKET'|'MANGLER_BANE', baner: string[]}>}
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

    const traef = bookinger.filter((b) => {
      const bs = new Date(b.start).getTime();
      if (b.slut) {
        return bs < slut && new Date(b.slut).getTime() > start;   // overlap
      }
      // Bookli giver kun starttid i listeformen; sluttid og banenavn
      // følger kun med når en booking hentes enkeltvis. Uden sluttid
      // tælles en booking med hvis den starter inden for kampens vindue
      // plus tre timer — hellere det end at kalde en booket bane manglende.
      return bs >= start - 3 * 3600000 && bs <= slut + 3 * 3600000;
    });

    return {
      kamp: k,
      status: traef.length ? 'BOOKET' : 'MANGLER_BANE',
      // Tom liste betyder ikke "ingen bane" — kun at Bookli ikke oplyste
      // navnet i listeformen.
      baner: traef.map((b) => b.bane).filter(Boolean),
      baneNavnKendt: traef.some((b) => b.bane),
      bookinger: traef,
    };
  });
}

/// Booker baner.
///
/// IKKE gennemført. Flowet bag "Opret booking" har jeg ikke haft foran
/// mig, og en booking optager en rigtig bane og trækker point på kontoen
/// — den slags skrives ikke på et gæt og afprøves ikke "lige for at se".
///
/// Valideringen ovenfor dækker det meste af behovet: den fortæller hvilke
/// hjemmekampe der mangler baner, og så kan et menneske booke dem.
export async function bookBane(_side, _booking) {
  throw new Error(
    'Selve bookingen er ikke skrevet endnu. Booking-fladen skal ses ' +
    'først — den optager en bane og koster point, så den skrives ikke ' +
    'på formodning. Brug validerBaner til at finde hvad der mangler.');
}
