// Fælles browser-opsætning.
import { chromium } from 'playwright';
import { config } from './config.js';

export async function medBrowser(arbejde) {
  const browser = await chromium.launch({ headless: config.headless });
  try {
    const ctx = await browser.newContext({
      locale: 'da-DK',
      timezoneId: 'Europe/Copenhagen',
      viewport: { width: 1400, height: 900 },
    });
    const side = await ctx.newPage();
    return await arbejde(side);
  } finally {
    await browser.close();
  }
}
