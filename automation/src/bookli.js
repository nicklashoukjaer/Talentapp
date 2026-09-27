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

/// Henter brugerens bookinger.
///
/// Læser Booklis egen GraphQL-API frem for at skrabe teksten. Kortene i
/// kalenderen viser hverken dato eller år — kun klokkeslæt — mens API'en
/// giver præcise tidsstempler og banens navn. At udlede datoen af en
/// kalendervisning ville være gætværk.
export async function hentBookinger(side) {
  const fundne = new Map();

  const lyt = async (svar) => {
    if (!/\/graphql/.test(svar.url())) return;
    let data;
    try { data = await svar.json(); } catch { return; }
    // Bookingerne kommer både enkeltvis og i lister.
    const saml = (o) => {
      if (!o || typeof o !== 'object') return;
      if (o.__typename === 'ResourceBooking' && o.startDate) {
        fundne.set(o.id ?? `${o.startDate}-${o.resource?.name ?? ''}`, {
          id: o.id ?? null,
          start: o.startDate,
          slut: o.endDate ?? null,
          bane: (o.resource?.name ?? '').replace(/^\[|\].*$/g, '').trim() || null,
          baneFuld: o.resource?.name ?? null,
        });
      }
      for (const v of Object.values(o)) {
        if (Array.isArray(v)) v.forEach(saml);
        else if (v && typeof v === 'object') saml(v);
      }
    };
    saml(data?.data);
  };

  side.on('response', lyt);
  try {
    await side.goto('https://bookli.app/u/calendar',
      { waitUntil: 'networkidle', timeout: 45000 });
    await side.waitForTimeout(5000);
  } finally {
    side.off('response', lyt);
  }

  if (/sign-in/.test(side.url())) {
    throw new Error('Bookli sendte tilbage til login — er lokationen valgt?');
  }
  return [...fundne.values()].sort((a, b) => a.start.localeCompare(b.start));
}

/// Sammenholder klubbens hjemmekampe med det der faktisk er booket.
///
/// En kamp regnes som dækket hvis en booking OVERLAPPER dens tidsrum på
/// samme dag. Der kræves ikke nøjagtigt samme klokkeslæt: en kamp kl.
/// 11–14 kan sagtens have en bane booket 11–12 og en anden 12–14.
///
/// @returns {Array<{kamp, status: 'BOOKET'|'MANGLER_BANE', baner: string[]}>}
export async function validerBaner(side, hjemmekampe) {
  const bookinger = await hentBookinger(side);

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
