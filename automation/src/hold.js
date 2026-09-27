// Holdene og deres RankedIn-link — hentet fra databasen, ikke fra en fil.
//
// RankedIn opretter nye hold-id'er hver sæson. Ligger linket i .env, skal
// nogen huske at rette det på den maskine der kører robotten. Ligger det i
// databasen, retter en admin det i appen, og robotten følger med af sig
// selv ved næste kørsel.
//
// Kræver SERVICE-nøglen. Politikken groups_read gælder kun rollen
// 'authenticated', så den offentlige nøgle får en TOM liste — uden fejl.
// Det ville ligne "ingen hold har et link" og sende fejlsøgningen det
// forkerte sted hen, så det fanges udtrykkeligt herunder.
import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';

let _klient = null;
function klient() {
  if (_klient) return _klient;
  const noegle = config.serviceKey || process.env.SUPABASE_ANON_KEY;
  if (!config.supabaseUrl || !noegle) {
    throw new Error('SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY mangler i .env');
  }
  _klient = createClient(config.supabaseUrl, noegle, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return _klient;
}

/// Alle hold med et RankedIn-link. Hold uden link springes over — fx
/// Damerne, indtil en admin skriver deres ind.
export async function holdMedRankedIn() {
  const { data, error } = await klient()
    .from('groups')
    .select('id, navn, rankedin_url, sort')
    .order('sort', { ascending: true });
  if (error) throw error;

  const alle = data ?? [];
  // Ingen hold OVERHOVEDET betyder ikke at klubben er tom — det betyder at
  // nøglen ikke må læse tabellen. Uden dette tjek ville en manglende
  // service-nøgle se ud som manglende data.
  if (alle.length === 0) {
    throw new Error(
      'Kunne ikke læse hold fra databasen. groups må kun læses af ' +
      'indloggede, så robotten skal bruge SUPABASE_SERVICE_ROLE_KEY — ' +
      'den offentlige nøgle giver en tom liste uden fejl.');
  }
  return alle.filter((g) => (g.rankedin_url || '').trim());
}

/// Ét hold slået op på navn, fx 'Talentløse 1'.
export async function holdVedNavn(navn) {
  const alle = await holdMedRankedIn();
  return alle.find((g) => g.navn === navn) ?? null;
}

/// Hold-id'et ud af adressen. .../team/homepage/3281091 → '3281091'
/// Skrivemåden varierer (homepage/homePage), så der matches uden hensyn
/// til store og små bogstaver.
export function rankedinId(url) {
  const m = String(url || '').match(/\/team\/homepage\/(\d+)/i);
  return m ? m[1] : null;
}
