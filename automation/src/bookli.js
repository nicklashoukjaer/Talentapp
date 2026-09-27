// Bookli-driver.
//
// FASE 1: skelettet står, men selve klikkene er IKKE skrevet. Bookli har
// ingen offentlig API, så det bliver browserstyring — og den skal skrives
// mod den rigtige side, ikke mod et gæt. At lade den fejle tydeligt er
// bedre end at lade som om den booker noget.
import { chromium } from 'playwright';
import { config } from './config.js';

export async function medBrowser(arbejde) {
  const browser = await chromium.launch({ headless: true });
  try {
    const ctx = await browser.newContext({ locale: 'da-DK' });
    return await arbejde(await ctx.newPage());
  } finally {
    await browser.close();
  }
}

export async function logInd(side) {
  if (!config.bookli.bruger || !config.bookli.kode) {
    throw new Error('Bookli-login mangler i .env');
  }
  await side.goto(config.bookli.url, { waitUntil: 'domcontentloaded' });
  // TODO(fase 2): udfyld mod den faktiske login-formular.
  throw new Error('Bookli-login er ikke implementeret endnu (fase 2)');
}

/**
 * Booker baner til en post fra køen.
 * @returns {Promise<string>} Booklis reference, så bookingen kan findes igen.
 */
export async function bookBane(_side, _booking) {
  // TODO(fase 2): vælg dato, klokkeslæt og antal baner, og bekræft.
  throw new Error('Banebooking er ikke implementeret endnu (fase 2)');
}

/** Flytter en eksisterende booking — bruges når en hjemmekamp rykkes. */
export async function flytBooking(_side, _eksternRef, _nyStart, _nySlut) {
  throw new Error('Flytning er ikke implementeret endnu (fase 2)');
}
