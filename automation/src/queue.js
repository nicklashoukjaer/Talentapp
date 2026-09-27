// Køen: hent arbejde, marker det i gang, skriv resultatet tilbage.
//
// Der tages ÉN post ad gangen og den markeres 'i_gang' med det samme, så to
// robotter ikke kan komme til at booke den samme bane to gange.
import { db } from './supabase.js';
import { config } from './config.js';

/** Næste godkendte booking. Kun godkendte — intet bookes uden et menneske. */
export async function naesteBooking() {
  const { data, error } = await db
    .from('pending_bookings')
    .select('*')
    .eq('status', 'godkendt')
    .lt('forsoeg', config.maxForsoeg)
    .order('oensket_start', { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data ?? null;
}

/** Markerer posten i gang. Returnerer false hvis en anden nåede den først. */
export async function tagBooking(id, forsoeg) {
  const { data, error } = await db
    .from('pending_bookings')
    .update({ status: 'i_gang', forsoeg: forsoeg + 1 })
    .eq('id', id)
    .eq('status', 'godkendt')   // optimistisk lås
    .select('id');
  if (error) throw error;
  return (data ?? []).length > 0;
}

export async function bookingLykkedes(id, eksternRef) {
  const { error } = await db
    .from('pending_bookings')
    .update({ status: 'booket', ekstern_ref: eksternRef ?? null, sidste_fejl: null })
    .eq('id', id);
  if (error) throw error;
}

/**
 * Lægger posten tilbage i køen, eller giver op hvis den har brugt sine
 * forsøg. En post der fejler igen og igen skal ses af et menneske, ikke
 * køre i ring.
 */
export async function bookingFejlede(id, forsoeg, fejl) {
  const opgiv = forsoeg + 1 >= config.maxForsoeg;
  const { error } = await db
    .from('pending_bookings')
    .update({
      status: opgiv ? 'fejlet' : 'godkendt',
      sidste_fejl: String(fejl).slice(0, 1000),
    })
    .eq('id', id);
  if (error) throw error;
  return opgiv;
}

/** Afsluttede afstemninger hvis datoer endnu mangler en booking. */
export async function datoerKlarTilBooking() {
  const { data, error } = await db
    .from('afstemninger_klar_til_booking')
    .select('*')
    .eq('booking_i_koe', false);
  if (error) throw error;
  return data ?? [];
}

export async function naesteRankedinOpgave() {
  const { data, error } = await db
    .from('rankedin_sync')
    .select('*')
    .eq('status', 'afventer')
    .lt('forsoeg', config.maxForsoeg)
    .order('oprettet_at', { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data ?? null;
}
