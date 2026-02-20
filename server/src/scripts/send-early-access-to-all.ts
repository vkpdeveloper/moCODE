import 'dotenv/config';

import { db } from "../db/client";
import { earlyAccessEmails } from "../db/schema";
import { sendEarlyAccessEmail } from "../lib/email";
import { sql } from "drizzle-orm";

async function main() {
  const emails = await db.select({ email: earlyAccessEmails.email }).from(earlyAccessEmails);
  
  if (emails.length === 0) {
    console.log("No early access emails found in the database.");
    return;
  }

  console.log(`Found ${emails.length} early access emails. Sending...\n`);
  
  let success = 0;
  let failed = 0;

  for (const { email } of emails) {
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
  console.log(`Total: ${emails.length}`);
  console.log(`Sent: ${success}`);
  console.log(`Failed: ${failed}`);
}

main();
