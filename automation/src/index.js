// Robotten. Kører i løkke, eller én gang med --once.
//
//   npm run worker:dry    læser køen og rapporterer, rører ingenting
//   npm run worker:once   tømmer køen én gang
//   npm run worker        kører videre med fast interval
import { config } from './config.js';
import {
  naesteBooking, tagBooking, bookingLykkedes, bookingFejlede,
  datoerKlarTilBooking, naesteRankedinOpgave,
} from './queue.js';
import { medBrowser } from './browser.js';
import { logInd, bookBane } from './bookli.js';

const log = (...a) => console.log(new Date().toISOString(), ...a);

async function behandlBookinger() {
  const booking = await naesteBooking();
  if (!booking) return false;

  log(`booking ${booking.id} · ${booking.oensket_start} · ${booking.antal_baner} bane(r)`);
  if (config.toerloeb) {
    log('  tørløb — rører ingenting');
    return false;
  }

  if (!(await tagBooking(booking.id, booking.forsoeg))) {
    log('  en anden nåede den først');
    return true;
  }

  try {
    const ref = await medBrowser(async (side) => {
      await logInd(side);
      return bookBane(side, booking);
    });
    await bookingLykkedes(booking.id, ref);
    log(`  booket · ${ref}`);
  } catch (fejl) {
    const opgav = await bookingFejlede(booking.id, booking.forsoeg, fejl);
    log(`  fejlede${opgav ? ' — opgivet, se den i appen' : ', prøver igen'}: ${fejl.message}`);
  }
  return true;
}

async function rapporterKandidater() {
  const klar = await datoerKlarTilBooking();
  if (klar.length === 0) return;
  log(`${klar.length} afstemte dato(er) mangler en booking:`);
  for (const k of klar.slice(0, 10)) {
    log(`  ${k.option_tid} · ${k.afstemning} · ${k.antal_ja} ja`);
  }
  // Der oprettes bevidst INGEN bookinger herfra. En booking koster penge og
  // en bane, så et menneske skal sige ja først.
}

async function runde() {
  await rapporterKandidater();
  let arbejde = true;
  while (arbejde) arbejde = await behandlBookinger();

  const ri = await naesteRankedinOpgave();
  if (ri) log(`rankedin-opgave ${ri.id} (${ri.slags}) — afventer fase 2`);
}

async function main() {
  log(`automation-bro starter${config.toerloeb ? ' (tørløb)' : ''}`);
  if (config.enGang) {
    await runde();
    return;
  }
  for (;;) {
    try {
      await runde();
    } catch (fejl) {
      log('runde fejlede:', fejl.message);
    }
    await new Promise((r) => setTimeout(r, config.intervalSekunder * 1000));
  }
}

main().catch((fejl) => {
  console.error(fejl);
  process.exit(1);
});
