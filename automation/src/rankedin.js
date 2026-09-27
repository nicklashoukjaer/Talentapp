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

/// Henter kampoversigten for et hold eller en turnering.
///
/// [sti] er den del af adressen der følger efter rankedin.com, fx
/// '/da/team/12345'. Den skal komme udefra: RankedIn har ingen offentlig
/// grænseflade, og holdets id kender vi ikke på forhånd.
export async function hentKampe(side, sti) {
  if (!sti) throw new Error('Angiv stien til holdet på RankedIn');
  await side.goto(config.rankedin.rodUrl + sti, {
    waitUntil: 'networkidle',
    timeout: 45000,
  });
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
