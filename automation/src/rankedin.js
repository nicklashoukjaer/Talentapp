// RankedIn-driver.
//
// FASE 1: samme forbehold som Bookli — skelettet står, klikkene mangler.
import { config } from './config.js';

export async function logInd(_side) {
  if (!config.rankedin.bruger || !config.rankedin.kode) {
    throw new Error('RankedIn-login mangler i .env');
  }
  throw new Error('RankedIn-login er ikke implementeret endnu (fase 2)');
}

export async function synkroniser(_side, _opgave) {
  throw new Error('RankedIn-synkronisering er ikke implementeret endnu (fase 2)');
}
