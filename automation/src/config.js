// Opsætning læst fra miljøet. Intet hemmeligt står i koden.
import { readFileSync } from 'node:fs';

function laesEnvFil() {
  try {
    const raw = readFileSync(new URL('../.env', import.meta.url), 'utf8');
    for (const linje of raw.split('\n')) {
      const m = linje.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
    }
  } catch {
    // Ingen .env — så forventes variablerne sat i miljøet.
  }
}
laesEnvFil();

function kraev(navn) {
  const v = process.env[navn];
  if (!v) throw new Error(`Mangler ${navn} — se automation/.env.example`);
  return v;
}

export const config = {
  supabaseUrl: kraev('SUPABASE_URL'),
  serviceKey: kraev('SUPABASE_SERVICE_ROLE_KEY'),
  bookli: {
    url: process.env.BOOKLI_URL || 'https://bookli.app/u/home',
    bruger: process.env.BOOKLI_BRUGER || '',
    kode: process.env.BOOKLI_KODE || '',
  },
  rankedin: {
    bruger: process.env.RANKEDIN_BRUGER || '',
    kode: process.env.RANKEDIN_KODE || '',
  },
  intervalSekunder: Number(process.env.INTERVAL_SEKUNDER || 120),
  maxForsoeg: Number(process.env.MAX_FORSOEG || 3),
  // --dry-run: robotten læser og rapporterer, men rører hverken Bookli,
  // RankedIn eller status i databasen.
  toerloeb: process.argv.includes('--dry-run'),
  enGang: process.argv.includes('--once'),
};
