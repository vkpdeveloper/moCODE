import { Resend } from "resend";
import { env } from "./env";

const resend = new Resend(env.RESEND_API_KEY);

export interface SendEarlyAccessEmailParams {
  to: string;
  name?: string | null;
}

export async function sendEarlyAccessEmail({
  to,
  name,
}: SendEarlyAccessEmailParams) {
  const appLink =
    "https://play.google.com/store/apps/details?id=com.mocode.app";
  const discountCode = "EARLY_MOCODE";

  const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f5f5f5;">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto; background-color: #ffffff;">
    <tr>
      <td style="padding: 40px 30px; text-align: center;">
        <h1 style="margin: 0 0 10px; font-size: 28px; font-weight: 700; color: #1a1a2e;">moCODE</h1>
        <p style="margin: 0; color: #666; font-size: 16px;">Your Early Access is Here</p>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px;">
        <p style="margin: 0 0 20px; color: #333; font-size: 16px; line-height: 1.6;">
          ${name ? `Hi ${name},` : "Hi there,"}
        </p>
        <p style="margin: 0 0 20px; color: #333; font-size: 16px; line-height: 1.6;">
          Welcome to moCODE! You've been granted <strong>Early Access</strong> — thank you for joining us on this journey.
        </p>
        <p style="margin: 0 0 30px; color: #333; font-size: 16px; line-height: 1.6;">
          As an Early Access member, you get <strong>100% OFF</strong> the full moCODE experience. No catch, no hidden fees — just your exclusive access to start building.
        </p>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px; text-align: center;">
        <a href="${appLink}" style="display: inline-block; padding: 16px 32px; background-color: #4f46e5; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 8px;">Download on Google Play</a>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px;">
        <div style="background-color: #f9fafb; border-radius: 8px; padding: 20px; text-align: center;">
          <p style="margin: 0 0 10px; color: #666; font-size: 14px;">Your Exclusive Discount Code</p>
          <p style="margin: 0; font-size: 24px; font-weight: 700; color: #1a1a2e; letter-spacing: 2px;">${discountCode}</p>
          <p style="margin: 10px 0 0; color: #666; font-size: 12px;">Use this code at checkout for 100% off</p>
        </div>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 40px;">
        <p style="margin: 0; color: #666; font-size: 14px; line-height: 1.6;">
          We're excited to have you on board. If you have any questions or feedback, just reply to this email — we'd love to hear from you.
        </p>
        <p style="margin: 20px 0 0; color: #666; font-size: 14px;">
          — The moCODE Team
        </p>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();

  const textContent = `
Hi${name ? ` ${name}` : " there"},

Welcome to moCODE! You've been granted Early Access — thank you for joining us on this journey.

As an Early Access member, you get 100% OFF the full moCODE experience. No catch, no hidden fees — just your exclusive access to start building.

Download on Google Play: ${appLink}

Your Exclusive Discount Code: ${discountCode}
Use this code at checkout for 100% off.

We're excited to have you on board. If you have any questions or feedback, just reply to this email — we'd love to hear from you.

— The moCODE Team
  `.trim();

  await resend.emails.send({
    from: "moCode <mocode@ordinity.com>",
    to,
    bcc: env.MY_EMAIL,
    subject: "🎉 You're In! Here's Your Early Access + 100% Off Code",
    html: htmlContent,
    text: textContent,
  });
}
