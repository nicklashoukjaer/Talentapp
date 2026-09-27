// Bro-grænsefladen: en lille HTTP-server appen kan spørge og sætte i gang.
//
// Bundet til 127.0.0.1 og kun 127.0.0.1. Robotten har klubbens logins og
// en service-nøgle der går uden om row level security — den må ikke kunne
// nås udefra. Dertil en delt nøgle, så en anden proces på samme maskine
// heller ikke kan kalde den ved et uheld.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { medBrowser } from './browser.js';
import * as bookli from './bookli.js';
import * as rankedin from './rankedin.js';
import { holdMedRankedIn } from './hold.js';

const PORT = Number(process.env.BRIDGE_PORT || 8787);
const TOKEN = process.env.BRIDGE_TOKEN || '';

// Appen kører på https://…vercel.app og broen på http://127.0.0.1.
// Uden disse svarhoveder blokerer browseren kaldet, og fejlen ses kun i
// konsollen — appen ville bare stå tavst uden bane-status.
//
// Browsere regner 127.0.0.1 som et sikkert ophav, så https → localhost er
// tilladt; men det kræver CORS, og Chrome kræver desuden
// Private-Network-Access-hovedet ved kald ind i det lokale net.
// ── Når broen står på internettet ────────────────────────────────────────
//
// Med en tunnel er broen ikke længere kun din maskine. Nøglen er det
// eneste der står imellem en fremmed og jeres Bookli-konto, så:
//   • nøgler sammenlignes tidskonstant, så de ikke kan gættes tegn for tegn
//   • forkerte forsøg tælles og spærres, så ingen kan prøve sig frem
//   • hvert kald logges, så misbrug kan SES frem for at ske i stilhed

const forsoeg = new Map();          // ip → { antal, indtil }
const MAX_FEJL = 10;
const SPAERRE_MS = 10 * 60 * 1000;

function noegleOk(givet) {
  if (!TOKEN) return true;          // ingen nøgle sat = ingen spærring
  const a = Buffer.from(String(givet ?? ''));
  const b = Buffer.from(TOKEN);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function spaerret(ip) {
  const f = forsoeg.get(ip);
  if (!f) return false;
  if (Date.now() > f.indtil) { forsoeg.delete(ip); return false; }
  return f.antal >= MAX_FEJL;
}

function taelFejl(ip) {
  const f = forsoeg.get(ip) ?? { antal: 0, indtil: 0 };
  f.antal += 1;
  f.indtil = Date.now() + SPAERRE_MS;
  forsoeg.set(ip, f);
}

function log(req, ip, udfald) {
  const sti = (req.url || '').split('?')[0];
  console.log(
    `${new Date().toISOString()}  ${ip.padEnd(15)} ${req.method} ${sti}  ${udfald}`);
}

function cors(res) {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-headers', 'content-type, x-bridge-token');
  res.setHeader('access-control-allow-methods', 'GET, POST, OPTIONS');
  res.setHeader('access-control-allow-private-network', 'true');
  res.setHeader('access-control-max-age', '86400');
}

function svar(res, kode, krop) {
  cors(res);
  res.writeHead(kode, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(krop, null, 1));
}

async function krop(req) {
  const dele = [];
  for await (const d of req) dele.push(d);
  if (!dele.length) return {};
  try { return JSON.parse(Buffer.concat(dele).toString()); } catch { return {}; }
}

// ── Appen serveres fra broen selv ─────────────────────────────────────────
//
// Chrome spærrer nu for at et offentligt websted rører 127.0.0.1:
// "Permission was denied for this request to access the loopback address".
// CORS-hovederne er ikke nok længere — det kræver brugerens tilladelse.
//
// I stedet serveres appen HERFRA. Så er app og bro samme oprindelse, og
// hverken CORS, blandet indhold eller loopback-spærringen findes.
// Åbn http://127.0.0.1:8787/app
// fileURLToPath, ikke .pathname: stien indeholder et mellemrum ("Gammel
// pc"), og .pathname efterlader det som %20 — så finder readFile intet.
const APP_ROD = fileURLToPath(new URL('../../build/web/', import.meta.url));

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2',
  '.map': 'application/json',
};

async function serverApp(req, res, sti) {
  let rel = sti.replace(/^\/app\/?/, '') || 'index.html';
  // Ingen vej ud af mappen.
  rel = normalize(rel).replace(/^(\.\.[/\\])+/, '');
  const filsti = join(APP_ROD, rel);
  try {
    const data = await readFile(filsti);
    res.writeHead(200, {
      'content-type': MIME[extname(filsti)] || 'application/octet-stream',
      // Flutters wasm kræver disse for at bruge delt hukommelse.
      'cross-origin-opener-policy': 'same-origin',
      'cross-origin-embedder-policy': 'credentialless',
    });
    return res.end(data);
  } catch {
    // Ukendt sti → index.html, så appens egen navigation virker.
    if (rel !== 'index.html') return serverApp(req, res, '/app/');
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('Appen er ikke bygget. Kør: flutter build web --wasm --release');
  }
}

const ruter = {
  // Er broen i live, og kan den logge ind?
  //
  // Både GET og POST. Flutter-klienten sender POST til alt, og en 404 her
  // ligner "broen svarer ikke" i appen — selvom kaldet kom frem og nøglen
  // var rigtig. Netop dét kostede en fejlsøgning.
  'GET /status': async () => ({
    oppe: true,
    headless: config.headless,
    bookli: Boolean(process.env.BOOKLI_EMAIL),
    rankedin: Boolean(process.env.RANKEDIN_USERNAME),
  }),

  // Samme svar på POST, se ovenfor.
  'POST /status': async () => ruter['GET /status'](),

  // Tjekker om der er baner i Bookli til de hjemmekampe appen sender med.
  'POST /bookli/valider': async (b) => {
    const kampe = (b.kampe || []).map((k) => ({ ...k, start: new Date(k.start) }));
    return medBrowser(async (side) => {
      await bookli.logInd(side);
      return { resultat: await bookli.validerBaner(side, kampe) };
    });
  },

  // Henter kampprogrammet for ét hold, eller for alle hold med et link.
  'POST /rankedin/kampe': async (b) =>
    medBrowser(async (side) => {
      await rankedin.logInd(side);
      if (b.url || b.sti) {
        return { kampe: await rankedin.hentKampe(side, b.url || b.sti) };
      }
      const ud = {};
      for (const g of await holdMedRankedIn()) {
        ud[g.navn] = await rankedin.hentKampe(side, g.rankedin_url);
      }
      return { hold: ud };
    }),

  // Stilling, pulje og sæson for hvert hold.
  'POST /rankedin/stilling': async () =>
    medBrowser(async (side) => {
      await rankedin.logInd(side);
      const ud = {};
      for (const g of await holdMedRankedIn()) {
        ud[g.navn] = await rankedin.hentHold(side, g.rankedin_url);
      }
      return { hold: ud };
    }),

  // Booking — findes som rute, men svarer ærligt at den ikke er skrevet.
  'POST /bookli/book': async (b) =>
    medBrowser(async (side) => {
      await bookli.logInd(side);
      return { resultat: await bookli.bookBane(side, b) };
    }),
};

createServer(async (req, res) => {
  const sti = (req.url || '').split('?')[0];
  const noegle = `${req.method} ${sti}`;

  // Browserens forespørgsel om lov. Den bærer ikke nøglen, så den skal
  // besvares FØR nøglen kontrolleres.
  // Appen serveres uden nøgle — det er jo bare filerne.
  if (sti === '/app' || sti.startsWith('/app/')) {
    return serverApp(req, res, sti);
  }

  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204);
    return res.end();
  }

  const ip = (req.headers['cf-connecting-ip']
      || req.socket.remoteAddress || '?').toString();

  if (spaerret(ip)) {
    log(req, ip, 'SPÆRRET');
    return svar(res, 429, { fejl: 'For mange forkerte forsøg. Prøv om 10 minutter.' });
  }
  if (!noegleOk(req.headers['x-bridge-token'])) {
    taelFejl(ip);
    log(req, ip, 'AFVIST (forkert nøgle)');
    return svar(res, 401, { fejl: 'Forkert eller manglende x-bridge-token' });
  }
  forsoeg.delete(ip);
  const rute = ruter[noegle];
  if (!rute) {
    log(req, ip, 'UKENDT RUTE');
    return svar(res, 404, { fejl: `Ukendt rute: ${noegle}` });
  }

  try {
    svar(res, 200, await rute(await krop(req)));
    log(req, ip, 'ok');
  } catch (e) {
    // Fejlen sendes videre som den er: beskeden fortæller hvad der mangler,
    // fx at booking-fladen ikke er skrevet, eller at Bookli venter på et
    // lokationsvalg. En generisk "noget gik galt" ville skjule netop det
    // der gør fejlen brugbar.
    log(req, ip, 'FEJL: ' + e.message.split('\n')[0].slice(0, 70));
    svar(res, 500, { fejl: e.message, status: 'FEJL' });
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`bro lytter på http://127.0.0.1:${PORT}`);
  console.log(`appen: http://127.0.0.1:${PORT}/app`);
  if (!TOKEN) {
    console.log('ADVARSEL: BRIDGE_TOKEN er tom — broen står helt åben');
  }
});
