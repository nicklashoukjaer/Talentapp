// Opsætning læst fra .env via dotenv. Intet hemmeligt står i koden.
import 'dotenv/config';

function kraev(navn) {
  const v = process.env[navn];
  if (!v) throw new Error(`Mangler ${navn} — se automation/.env.example`);
  return v;
}

export const config = {
  supabaseUrl: process.env.SUPABASE_URL || '',
  serviceKey: process.env.SUPABASE_SERVICE_ROLE_KEY || '',

  bookli: {
    // Login-siden, ikke /u/home: den sender alligevel videre hertil.
    loginUrl: 'https://bookli.app/sign-in',
    hjemUrl: process.env.BOOKLI_URL || 'https://bookli.app/u/home',
    // Klubben hvor T1 og T2 spiller hjemme. RankedIn oplyser den som
    // "Padel Club Hjørring" på begge holds sider.
    lokation: process.env.BOOKLI_LOKATION || 'Padel Club Hjørring',
    get email() { return kraev('BOOKLI_EMAIL'); },
    get kode() { return kraev('BOOKLI_PASSWORD'); },
  },

  rankedin: {
    loginUrl: 'https://www.rankedin.com/en/account/login',
    rodUrl: process.env.RANKEDIN_URL || 'https://www.rankedin.com',
    get bruger() { return kraev('RANKEDIN_USERNAME'); },
    get kode() { return kraev('RANKEDIN_PASSWORD'); },
  },

  intervalSekunder: Number(process.env.INTERVAL_SEKUNDER || 120),
  maxForsoeg: Number(process.env.MAX_FORSOEG || 3),
  // HEADLESS=0 åbner et synligt vindue. Uundværligt når selektorer skal
  // skrives mod en side man ikke kan se.
  headless: process.env.HEADLESS !== '0',

  toerloeb: process.argv.includes('--dry-run'),
  enGang: process.argv.includes('--once'),
};

/// Kaster hvis Supabase ikke er sat op. Playwright-delen kan køre uden.
export function kraevSupabase() {
  if (!config.supabaseUrl || !config.serviceKey) {
    throw new Error(
      'SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY mangler i .env');
  }
}
