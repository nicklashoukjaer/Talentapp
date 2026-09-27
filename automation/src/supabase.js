// Databaseklient til robotten.
//
// Bruger service-nøglen og går dermed UDEN OM row level security. Den må
// kun findes på den maskine der kører robotten — aldrig i Flutter-appen og
// aldrig i git.
import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';

export const db = createClient(config.supabaseUrl, config.serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
