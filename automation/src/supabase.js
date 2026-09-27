// Databaseklient til robotten.
//
// Oprettes DOVENT. Før lå den som en konstant, og så væltede hele broen
// ved import hvis SUPABASE_SERVICE_ROLE_KEY ikke var sat — også når man
// bare ville afprøve Bookli eller RankedIn, som intet har med den at gøre.
import { createClient } from '@supabase/supabase-js';
import { config, kraevSupabase } from './config.js';

let _klient = null;

export function db() {
  if (_klient) return _klient;
  kraevSupabase();
  _klient = createClient(config.supabaseUrl, config.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return _klient;
}
