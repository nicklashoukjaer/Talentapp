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

/// Henter brugerens bookinger som de står i Bookli.
///
/// Returnerer rå linjer indtil strukturen bag lokationsvalget er set. At
/// gætte på markup vi aldrig har haft foran os ville give selektorer der
/// fejler stille — og en stille fejl er værre end ingen funktion.
export async function hentBookinger(side) {
  await side.goto(config.bookli.hjemUrl, {
    waitUntil: 'networkidle',
    timeout: 45000,
  }).catch(() => {});
  await side.waitForTimeout(3000);
  if (/sign-in/.test(side.url())) {
    throw new Error('Bookli sendte tilbage til login — ingen lokation valgt?');
  }
  const linjer = await side
    .$$eval('[class*=booking], [class*=reservation], li, tr', (els) =>
      els.map((e) => (e.innerText || '').trim())
         .filter((t) => t && t.length < 200))
    .catch(() => []);
  return [...new Set(linjer)];
}

/// Sammenholder klubbens hjemmekampe med det der faktisk står i Bookli.
///
/// @param {Array<{id:string,titel:string,start:Date}>} hjemmekampe
/// @returns {Promise<Array<{kamp:object, fundet:boolean}>>}
export async function validerBaner(side, hjemmekampe) {
  const bookinger = await hentBookinger(side);
  return hjemmekampe.map((k) => {
    const dag = String(k.start.getDate()).padStart(2, '0');
    const maaned = String(k.start.getMonth() + 1).padStart(2, '0');
    // Bookli skriver datoer på flere måder; der ledes bredt og rapporteres
    // frem for at konkludere. Et falsk "booket" er værre end et spørgsmål.
    const fundet = bookinger.some(
      (b) => b.includes(`${dag}.${maaned}`) || b.includes(`${dag}/${maaned}`));
    return { kamp: k, fundet };
  });
}

export async function bookBane(_side, _booking) {
  throw new Error(
    'Banebooking kan først skrives når lokationen er valgt og ' +
    'booking-fladen har været set. Se README.');
}
