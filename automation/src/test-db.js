// Afprøver at robotten kan læse holdenes RankedIn-links.
//
// Det er service-nøglen der afgør det: groups må kun læses af indloggede,
// så den offentlige nøgle giver en TOM liste uden fejl. Derfor tjekkes
// både at der kommer hold, og at de kommer med links.
import { holdMedRankedIn, rankedinId } from './hold.js';

try {
  const hold = await holdMedRankedIn();
  console.log(`Databaselæsning … OK (${hold.length} hold med link)`);
  for (const g of hold) {
    const id = rankedinId(g.rankedin_url);
    console.log(`  ${g.navn.padEnd(18)} id ${id ?? '(kunne ikke læses)'}`);
  }
  if (hold.length === 0) {
    console.log('  ADVARSEL: ingen hold har et RankedIn-link endnu.');
  }
  process.exit(0);
} catch (e) {
  console.log('Databaselæsning … FEJL —', e.message.split('\n')[0]);
  process.exit(1);
}
