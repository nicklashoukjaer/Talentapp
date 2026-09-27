// RankedIn-driver.
//
// Selektorerne er AFLÆST fra den kørende side, ikke gættet:
//   input[name=UserName]  type=email    placeholder "Email address"
//   input[name=Password]  type=password placeholder "Password"
//   input[name=RememberMe] checkbox
// Login ligger på /en/account/login; /da/login giver 404.
import { config } from './config.js';

/// Lukker samtykke-boksen.
///
/// RankedIn viser en cookie-boks der LIGGER OVEN PÅ siden. Uden at lukke
/// den rammer klik ved siden af, og brødteksten bliver samtykke-teksten i
/// stedet for indholdet — det kostede en del fejlsøgning at opdage.
export async function lukSamtykke(side) {
  for (const t of ['Acceptér alle', 'Accept all', 'Accepter alle', 'Godkend alle']) {
    const k = side.locator(`button:has-text("${t}")`).first();
    if (await k.count().catch(() => 0)) {
      await k.click({ timeout: 4000 }).catch(() => {});
      await side.waitForTimeout(1200);
      return true;
    }
  }
  return false;
}

export async function logInd(side) {
  await side.goto(config.rankedin.loginUrl, {
    waitUntil: 'networkidle',
    timeout: 45000,
  });
  await lukSamtykke(side);
  await side.fill('input[name="UserName"]', config.rankedin.bruger);
  await side.fill('input[name="Password"]', config.rankedin.kode);
  await side.press('input[name="Password"]', 'Enter');
  await side.waitForTimeout(5000);

  if (/account\/login/.test(side.url())) {
    const fejl = await side
      .$$eval('.validation-summary-errors, .field-validation-error, .alert',
        (els) => els.map((e) => (e.innerText || '').trim()).filter(Boolean))
      .catch(() => []);
    throw new Error(
      'RankedIn-login afvist' + (fejl.length ? ': ' + fejl.join(' · ') : '') +
      ' — tjek RANKEDIN_USERNAME og RANKEDIN_PASSWORD');
  }
  return true;
}

/// Henter holdets side: stamdata og stillingen i puljen.
///
/// Felterne herunder er AFLÆST fra en rigtig holdside (T1, 3281091), ikke
/// gættet: sæsonen står i sidens titel, og "Home Club", "Court", "Pool",
/// "Members" og "ID" står som mærkater i brødteksten.
export async function hentHold(side, url) {
  if (!url) throw new Error('Holdets RankedIn-adresse mangler');
  await side.goto(url, { waitUntil: 'networkidle', timeout: 45000 });
  await lukSamtykke(side);
  await side.waitForTimeout(2500);

  const titel = await side.title();
  const tekst = await side.innerText('body').catch(() => '');

  const efter = (maerkat) => {
    const m = tekst.match(new RegExp(maerkat + '\\s*:?\\s*\\n?\\s*(.+)'));
    return m ? m[1].trim() : null;
  };

  // Stillingen. Tabellen med "M. Points" i overskriften er puljen; de
  // øvrige tabeller på siden er forklaringer og hjælpetekst.
  const stilling = await side
    .$$eval('table', (tabeller) => {
      const t = tabeller.find((x) =>
        (x.querySelector('tr')?.innerText || '').includes('M. Points'));
      if (!t) return [];
      return [...t.querySelectorAll('tr')]
        .slice(1)
        .map((tr) =>
          [...tr.querySelectorAll('td, th')]
            .map((c) => (c.innerText || '').replace(/\s+/g, ' ').trim())
            .filter(Boolean))
        .filter((r) => r.length >= 3);
    })
    .catch(() => []);

  return {
    url,
    saeson: titel.replace(/\s*\|\s*Rankedin\s*$/i, '').trim() || null,
    hold: efter('Lunar Ligaen[^>]*>') || efter('Home Club') ? null : null,
    hjemmeklub: efter('Home Club'),
    bane: efter('Court'),
    pool: efter('Pool'),
    medlemmer: Number((tekst.match(/Members:\s*(\d+)/) || [])[1]) || null,
    rankedinId: (tekst.match(/ID:\s*(T\d+)/) || [])[1] || null,
    stilling,
  };
}

/// Henter holdets kampprogram: dato, hjemmehold, udehold og resultat.
///
/// Kampene ligger bag fanen "Matches" på holdsiden, i en tabel med
/// overskrifterne Date · Home · vs · Away · Results.
export async function hentKampe(side, urlEllerSti) {
  if (!urlEllerSti) throw new Error('Angiv holdets adresse på RankedIn');
  const url = /^https?:/.test(urlEllerSti)
      ? urlEllerSti
      : config.rankedin.rodUrl + urlEllerSti;

  await side.goto(url, { waitUntil: 'networkidle', timeout: 45000 });
  await lukSamtykke(side);
  await side.waitForTimeout(1500);

  const fane = side.locator('a,button').filter({ hasText: /^Matches$/ }).first();
  if (await fane.count().catch(() => 0)) {
    await fane.click({ timeout: 5000 }).catch(() => {});
    await side.waitForTimeout(4000);
  }

  // Kamp-fanen har INGEN <table>. Den er bygget af div'er:
  //   .matches-table > .matches-body > .match-row
  // Standings-fanen bruger derimod en rigtig tabel — de to faner er ikke
  // bygget ens, og det kostede en runde at opdage.
  const raekker = await side
    .$$eval('.match-row', (raekker) =>
      raekker.map((r) =>
        (r.innerText || '').split('\n').map((x) => x.trim()).filter(Boolean)))
    .catch(() => []);

  const erNiveau = (x) => /^\d+\.\d+$/.test(x);      // spillerens styrketal
  const erTid = (x) => /^\d{1,2}:\d{2}$/.test(x);
  const erResultat = (x) => /^\d+\s*-\s*\d+$/.test(x);

  return raekker
    .filter((l) => l.length && /\d{1,2}\/\d{1,2}\/\d{4}/.test(l[0]))
    .map((l) => {
      const dato = l[0];
      // "vs" deler hjemme fra ude. Styrketallene står mellem navnene og
      // hører ikke til holdnavnet.
      const vs = l.indexOf('vs');
      const foer = l.slice(1, vs < 0 ? 1 : vs).filter((x) => !erNiveau(x));
      const efter = l.slice(vs < 0 ? 1 : vs + 1).filter((x) => !erNiveau(x));
      const ude = efter[0] ?? null;
      const rest = efter.slice(1);

      return {
        dato,
        iso: dato.replace(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/,
            (_, d, m, y) => `${y}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`),
        tid: rest.find(erTid) ?? null,
        hjemme: foer[0] ?? null,
        ude,
        // "enter results" betyder at kampen ikke er spillet endnu.
        resultat: rest.find(erResultat) ?? null,
        spillet: rest.some(erResultat),
        spillested: rest.find((x) => x.includes(',')) ?? null,
        raa: l,
      };
    });
}

/// Flytter en kamp på RankedIn.
///
/// IKKE skrevet. Kampene har en "enter results"-knap og en admin-flade,
/// men den har jeg ikke haft foran mig. At gætte på formularen ville give
/// kode der fejler stille — eller værre, ændrer den forkerte kamp.
export async function flytKamp(_side, _kamp, _nyDato) {
  throw new Error(
    'Kampflytning på RankedIn er ikke skrevet endnu. Admin-fladen skal ' +
    'ses først — et gæt kunne ramme den forkerte kamp.');
}
