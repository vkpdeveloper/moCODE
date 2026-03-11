import 'dotenv/config';
import { Command } from 'commander';
import { db } from "../db/client";
import { earlyAccessEmails } from "../db/schema";
import { sendEarlyAccessReminderEmail } from "../lib/email";

const program = new Command();

program
  .option('-t, --test <email>', 'Send to a single test email address')
  .parse(process.argv);

const opts = program.opts();

async function main() {
  if (opts.test) {
    console.log(`Sending test email to: ${opts.test}`);
    try {
      await sendEarlyAccessReminderEmail({ to: opts.test });
      console.log(`✓ Test email sent successfully to ${opts.test}`);
    } catch (error) {
      console.error(`✗ Failed to send test email:`, error);
      process.exit(1);
    }
    return;
  }

  const emails = await db.select({ email: earlyAccessEmails.email }).from(earlyAccessEmails);
  
  if (emails.length === 0) {
    console.log("No early access emails found in the database.");
    return;
  }

  console.log(`Found ${emails.length} early access emails. Sending reminder...\n`);
  
  let success = 0;
  let failed = 0;

  for (const { email } of emails) {
    try {
      console.log(`Sending to: ${email}...`);
      await sendEarlyAccessReminderEmail({ to: email });
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
