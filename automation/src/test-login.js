// Afprøver at begge logins virker. Skriver ALDRIG kodeord ud.
import { medBrowser } from './browser.js';
import * as bookli from './bookli.js';
import * as rankedin from './rankedin.js';

async function proev(navn, fn) {
  process.stdout.write(`${navn.padEnd(10)} … `);
  try {
    await medBrowser(fn);
    console.log('OK');
    return true;
  } catch (e) {
    console.log('FEJL — ' + e.message.split('\n')[0]);
    return false;
  }
}

const a = await proev('Bookli', (s) => bookli.logInd(s));
const b = await proev('RankedIn', (s) => rankedin.logInd(s));
process.exit(a && b ? 0 : 1);
