import 'dotenv/config';

import { sendEarlyAccessEmail } from "../lib/email";

const emails = process.argv.slice(2);

if (emails.length === 0) {
  console.log("Usage: bun run src/scripts/send-early-access.ts <email1> <email2> ...");
  console.log("Example: bun run src/scripts/send-early-access.ts test@example.com another@example.com");
  process.exit(1);
}

async function main() {
  console.log(`Sending early access emails to ${emails.length} recipient(s)...\n`);
  
  let success = 0;
  let failed = 0;

  for (const email of emails) {
    try {
      console.log(`Sending to: ${email}...`);
      await sendEarlyAccessEmail({ to: email });
      console.log(`✓ Sent successfully to ${email}`);
      success++;
    } catch (error) {
      console.error(`✗ Failed to send to ${email}:`, error);
      failed++;
    }
  }

  console.log(`\n--- Summary ---`);
  console.log(`Sent: ${success}`);
  console.log(`Failed: ${failed}`);
}

main();
