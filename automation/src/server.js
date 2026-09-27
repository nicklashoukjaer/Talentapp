// Bro-grænsefladen: en lille HTTP-server appen kan spørge og sætte i gang.
//
// Bundet til 127.0.0.1 og kun 127.0.0.1. Robotten har klubbens logins og
// en service-nøgle der går uden om row level security — den må ikke kunne
// nås udefra. Dertil en delt nøgle, så en anden proces på samme maskine
// heller ikke kan kalde den ved et uheld.
import { createServer } from 'node:http';
import { config } from './config.js';
import { medBrowser } from './browser.js';
import * as bookli from './bookli.js';
import * as rankedin from './rankedin.js';

const PORT = Number(process.env.BRIDGE_PORT || 8787);
const TOKEN = process.env.BRIDGE_TOKEN || '';

function svar(res, kode, krop) {
  res.writeHead(kode, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(krop, null, 1));
}

async function krop(req) {
  const dele = [];
  for await (const d of req) dele.push(d);
  if (!dele.length) return {};
  try { return JSON.parse(Buffer.concat(dele).toString()); } catch { return {}; }
}

const ruter = {
  // Er broen i live, og kan den logge ind?
  'GET /status': async () => ({
    oppe: true,
    headless: config.headless,
    bookli: Boolean(process.env.BOOKLI_EMAIL),
    rankedin: Boolean(process.env.RANKEDIN_USERNAME),
  }),

  // Tjekker om der er baner i Bookli til de hjemmekampe appen sender med.
  'POST /bookli/valider': async (b) => {
    const kampe = (b.kampe || []).map((k) => ({ ...k, start: new Date(k.start) }));
    return medBrowser(async (side) => {
      await bookli.logInd(side);
      return { resultat: await bookli.validerBaner(side, kampe) };
    });
  },

  // Henter kampoversigten fra en RankedIn-side.
  'POST /rankedin/kampe': async (b) =>
    medBrowser(async (side) => {
      await rankedin.logInd(side);
      return { raekker: await rankedin.hentKampe(side, b.sti) };
    }),
};

createServer(async (req, res) => {
  const sti = (req.url || '').split('?')[0];
  const noegle = `${req.method} ${sti}`;

  if (TOKEN && req.headers['x-bridge-token'] !== TOKEN) {
    return svar(res, 401, { fejl: 'Forkert eller manglende x-bridge-token' });
  }
  const rute = ruter[noegle];
  if (!rute) return svar(res, 404, { fejl: `Ukendt rute: ${noegle}` });

  try {
    svar(res, 200, await rute(await krop(req)));
  } catch (e) {
    // Fejlen sendes videre som den er: beskeden fortæller hvad der mangler,
    // fx at Bookli venter på et lokationsvalg.
    svar(res, 500, { fejl: e.message });
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`bro lytter på http://127.0.0.1:${PORT}`);
  if (!TOKEN) console.log('ADVARSEL: BRIDGE_TOKEN er tom — sæt den i .env');
});
