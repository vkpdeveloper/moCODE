import { Resend } from "resend";
import { env } from "./env";

const resend = new Resend(env.RESEND_API_KEY);

const COLORS = {
  background: "#131010",
  surface: "#1A1616",
  surfaceVariant: "#221E1E",
  border: "#2E2A2A",
  borderLight: "#3A3535",
  textPrimary: "#E8E0E0",
  textSecondary: "#9A9090",
  textTertiary: "#6A6060",
  accent: "#FF6B35",
  accentDim: "#803518",
  success: "#4ADE80",
};

export interface SendEarlyAccessEmailParams {
  to: string;
  name?: string | null;
}

export async function sendEarlyAccessEmail({
  to,
  name,
}: SendEarlyAccessEmailParams) {
  const appLink =
    "https://play.google.com/store/apps/details?id=com.ordinity.mocode";
  const discountCode = "EARLY_MOCODE";

  const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: ${COLORS.background};">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto; background-color: ${COLORS.surface};">
    <tr>
      <td style="padding: 40px 30px; text-align: center; border-bottom: 1px solid ${COLORS.border};">
        <h1 style="margin: 0 0 8px; font-size: 32px; font-weight: 700; color: ${COLORS.textPrimary}; letter-spacing: -0.5px;">moCODE</h1>
        <p style="margin: 0; color: ${COLORS.textSecondary}; font-size: 15px;">Your AI-Powered Coding Companion</p>
      </td>
    </tr>
    <tr>
      <td style="padding: 40px 30px 0;">
        <p style="margin: 0 0 20px; color: ${COLORS.textPrimary}; font-size: 18px; line-height: 1.5;">
          ${name ? `Hey ${name}!` : "Hey there!"}
        </p>
        <p style="margin: 0 0 16px; color: ${COLORS.textPrimary}; font-size: 16px; line-height: 1.6;">
          Welcome to moCODE! You've been granted <strong style="color: ${COLORS.accent};">Early Access</strong> — thank you for joining us on this journey.
        </p>
        <p style="margin: 0 0 24px; color: ${COLORS.textSecondary}; font-size: 15px; line-height: 1.6;">
          As an Early Access member, you get <strong style="color: ${COLORS.success};">100% OFF</strong> the full moCODE experience. No catch, no hidden fees — just your exclusive access to start building.
        </p>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px; text-align: center;">
        <a href="${appLink}" style="display: inline-block; padding: 16px 40px; background-color: ${COLORS.accent}; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 0;">Download on Google Play</a>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px;">
        <div style="background-color: ${COLORS.surfaceVariant}; border: 1px solid ${COLORS.border}; border-radius: 0; padding: 24px; text-align: center;">
          <p style="margin: 0 0 8px; color: ${COLORS.textSecondary}; font-size: 13px; text-transform: uppercase; letter-spacing: 1px;">Your Exclusive Discount Code</p>
          <p style="margin: 0; font-size: 28px; font-weight: 700; color: ${COLORS.accent}; letter-spacing: 3px;">${discountCode}</p>
          <p style="margin: 12px 0 0; color: ${COLORS.textTertiary}; font-size: 13px;">Use this code at checkout for 100% off</p>
        </div>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 40px; border-top: 1px solid ${COLORS.border};">
        <p style="margin: 24px 0 0; color: ${COLORS.textSecondary}; font-size: 14px; line-height: 1.6;">
          We're excited to have you on board. If you have any questions or feedback, just reply to this email — we'd love to hear from you.
        </p>
        <p style="margin: 20px 0 0; color: ${COLORS.textTertiary}; font-size: 13px;">
          — The moCODE Team
        </p>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();

  const textContent = `
Hey${name ? ` ${name}` : " there"},

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

export interface SendEarlyAccessReminderEmailParams {
  to: string;
  name?: string | null;
}

export async function sendEarlyAccessReminderEmail({
  to,
  name,
}: SendEarlyAccessReminderEmailParams) {
  const appLink = "https://play.google.com/store/apps/details?id=com.ordinity.mocode";
  const discountCode = "EARLY_MOCODE";

  const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: ${COLORS.background};">
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto; background-color: ${COLORS.surface};">
    <tr>
      <td style="padding: 40px 30px; text-align: center; border-bottom: 1px solid ${COLORS.border};">
        <h1 style="margin: 0 0 8px; font-size: 32px; font-weight: 700; color: ${COLORS.textPrimary}; letter-spacing: -0.5px;">moCODE</h1>
        <p style="margin: 0; color: ${COLORS.textSecondary}; font-size: 15px;">Your AI-Powered Coding Companion</p>
      </td>
    </tr>
    <tr>
      <td style="padding: 40px 30px 0;">
        <p style="margin: 0 0 24px; color: ${COLORS.textPrimary}; font-size: 18px; line-height: 1.5;">
          ${name ? `Hey ${name}!` : "Hey there!"}
        </p>
        <p style="margin: 0 0 16px; color: ${COLORS.textPrimary}; font-size: 16px; line-height: 1.6;">
          Just a quick reminder that your <span style="color: ${COLORS.accent}; font-weight: 600;">Early Access</span> to moCODE on Google Play is waiting for you!
        </p>
        <p style="margin: 0 0 24px; color: ${COLORS.textSecondary}; font-size: 15px; line-height: 1.6;">
          We know life gets busy — but we didn't want you to miss out on your exclusive <strong style="color: ${COLORS.success};">100% OFF</strong> early access deal. This is your chance to be among the first to experience the future of coding with AI by your side.
        </p>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px; text-align: center;">
        <a href="${appLink}" style="display: inline-block; padding: 16px 40px; background-color: ${COLORS.accent}; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 0;">Get moCODE on Google Play</a>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px;">
        <div style="background-color: ${COLORS.surfaceVariant}; border: 1px solid ${COLORS.border}; border-radius: 0; padding: 24px; text-align: center;">
          <p style="margin: 0 0 8px; color: ${COLORS.textSecondary}; font-size: 13px; text-transform: uppercase; letter-spacing: 1px;">Your Early Access Code</p>
          <p style="margin: 0; font-size: 28px; font-weight: 700; color: ${COLORS.accent}; letter-spacing: 3px;">${discountCode}</p>
          <p style="margin: 12px 0 0; color: ${COLORS.textTertiary}; font-size: 13px;">Use this at checkout for 100% off — forever</p>
        </div>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 30px;">
        <p style="margin: 0; color: ${COLORS.textSecondary}; font-size: 14px; line-height: 1.6;">
          🔥 <strong style="color: ${COLORS.textPrimary};">Pro tip:</strong> Download now and start coding with AI in minutes. No setup required — just open the app and start building.
        </p>
      </td>
    </tr>
    <tr>
      <td style="padding: 0 30px 40px; border-top: 1px solid ${COLORS.border};">
        <p style="margin: 24px 0 0; color: ${COLORS.textSecondary}; font-size: 14px; line-height: 1.6;">
          Have questions or need help? Just reply to this email — we're here to help you get started.
        </p>
        <p style="margin: 20px 0 0; color: ${COLORS.textTertiary}; font-size: 13px;">
          — The moCODE Team
        </p>
      </td>
    </tr>
  </table>
  <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto;">
    <tr>
      <td style="padding: 0 30px 40px; text-align: center;">
        <p style="margin: 0; color: ${COLORS.textTertiary}; font-size: 12px;">
          Don't want to receive these reminders? <a href="#" style="color: ${COLORS.textSecondary}; text-decoration: underline;">Unsubscribe</a>
        </p>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();

  const textContent = `
Hey${name ? ` ${name}` : " there"},

Just a quick reminder that your Early Access to moCODE on Google Play is waiting for you!

We know life gets busy — but we didn't want you to miss out on your exclusive 100% OFF early access deal. This is your chance to be among the first to experience the future of coding with AI by your side.

Get moCODE on Google Play: ${appLink}

Your Early Access Code: ${discountCode}
Use this at checkout for 100% off — forever.

Pro tip: Download now and start coding with AI in minutes. No setup required — just open the app and start building.

Have questions or need help? Just reply to this email — we're here to help you get started.

— The moCODE Team
  `.trim();

  await resend.emails.send({
    from: "moCode <mocode@ordinity.com>",
    to,
    bcc: env.MY_EMAIL,
    subject: "⏰ Your Early Access is Waiting — Don't Miss Out!",
    html: htmlContent,
    text: textContent,
  });
}
