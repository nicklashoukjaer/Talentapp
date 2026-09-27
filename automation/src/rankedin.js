// RankedIn-driver.
//
// Selektorerne er AFLÆST fra den kørende side, ikke gættet:
//   input[name=UserName]  type=email    placeholder "Email address"
//   input[name=Password]  type=password placeholder "Password"
//   input[name=RememberMe] checkbox
// Login ligger på /en/account/login; /da/login giver 404.
import { config } from './config.js';

export async function logInd(side) {
  await side.goto(config.rankedin.loginUrl, {
    waitUntil: 'networkidle',
    timeout: 45000,
  });
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

/// Henter kampoversigten for et hold eller en turnering.
///
/// [sti] er den del af adressen der følger efter rankedin.com, fx
/// '/da/team/12345'. Den skal komme udefra: RankedIn har ingen offentlig
/// grænseflade, og holdets id kender vi ikke på forhånd.
export async function hentKampe(side, stiEllerUrl) {
  if (!stiEllerUrl) throw new Error('Angiv holdets adresse på RankedIn');
  const url = /^https?:/.test(stiEllerUrl)
      ? stiEllerUrl
      : config.rankedin.rodUrl + stiEllerUrl;
  await side.goto(url, { waitUntil: 'networkidle', timeout: 45000 });
  await side.waitForTimeout(2500);

  // Tabelrækker er den mest almindelige form på RankedIn. Der returneres
  // RÅ rækker frem for et fortolket resultat: uden at have set netop
  // jeres holdside ville en fortolkning være et gæt.
  const raekker = await side
    .$$eval('table tr', (els) =>
      els.map((tr) =>
        [...tr.querySelectorAll('td, th')]
          .map((c) => (c.innerText || '').trim())
          .filter(Boolean))
        .filter((r) => r.length > 1))
    .catch(() => []);
  return raekker;
}

export async function synkroniser(_side, _opgave) {
  throw new Error(
    'Synkronisering tilbage TIL RankedIn er ikke skrevet endnu. ' +
    'Læsning virker; skrivning kræver at vi har set den rigtige formular.');
}
