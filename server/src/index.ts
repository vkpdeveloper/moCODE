import { and, desc, eq, gte } from "drizzle-orm";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { serveStatic } from "@hono/node-server/serve-static";
import { Webhook } from "standardwebhooks";
import { z } from "zod";

import { db } from "./db/client";
import { accountDeletionRequests, checkoutSessions, entitlements } from "./db/schema";
import { corsOrigins, env } from "./lib/env";
import { createDodoCheckoutSession } from "./lib/dodo";
import { firebaseAuthMiddleware } from "./middleware/firebase-auth";

type Variables = {
  authUser: {
    id: string;
    firebaseUid: string;
    email: string;
    displayName: string | null;
  };
};

const webhookVerifier = new Webhook(env.DODO_WEBHOOK_SECRET);
const viewsDir = fileURLToPath(new URL("./views", import.meta.url));
const billingCompleteHtml = readFileSync(
  join(viewsDir, "billing-complete.html"),
  "utf8",
);
const landingHtml = readFileSync(join(viewsDir, "landing.html"), "utf8");
const privacyHtml = readFileSync(join(viewsDir, "privacy.html"), "utf8");
const termsHtml = readFileSync(join(viewsDir, "terms.html"), "utf8");

const createCheckoutSchema = z.object({
  quantity: z.number().int().min(1).max(10).default(1),
});

const accountDeletionSchema = z.object({
  email: z.string().trim().email(),
});

const app = new Hono<{ Variables: Variables }>();

app.use(
  "*",
  cors({
    origin: (origin) => {
      if (!origin || corsOrigins.includes("*")) {
        return origin ?? "*";
      }
      return corsOrigins.includes(origin) ? origin : (corsOrigins[0] ?? "");
    },
    allowMethods: ["GET", "POST", "OPTIONS"],
    allowHeaders: [
      "Content-Type",
      "Authorization",
      "webhook-id",
      "webhook-signature",
      "webhook-timestamp",
    ],
    exposeHeaders: ["Content-Length"],
    maxAge: 86400,
    credentials: true,
  }),
);

const PUBLIC_DIR = join(process.cwd(), "public");

app.use("/*", serveStatic({ root: PUBLIC_DIR }));

app.get("/", async (c) => c.html(landingHtml));

app.get("/privacy", async (c) => c.html(privacyHtml));

app.get("/terms", async (c) => c.html(termsHtml));

app.get("/account-deletion-request", async (c) => {
  return c.html(
    `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>moCODE - Account Deletion Request</title>
    <meta
      name="description"
      content="Request account deletion for moCODE."
    />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="moCODE - Account Deletion Request" />
    <meta
      property="og:description"
      content="Request account deletion for moCODE."
    />
    <meta property="og:image" content="/images/feature-cover-optimized.jpg" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="moCODE - Account Deletion Request" />
    <meta
      name="twitter:description"
      content="Request account deletion for moCODE."
    />
    <meta name="twitter:image" content="/images/feature-cover-optimized.jpg" />
    <link rel="icon" type="image/png" href="/app-icon.png" />
    <link rel="apple-touch-icon" href="/app-icon.png" />
    <link rel="stylesheet" href="/styles.css" />
  </head>
  <body>
    <div class="bg-pattern"></div>
    <div class="bg-grid"></div>

    <header class="header">
      <div class="container header-content">
        <a href="/" class="logo">moCODE</a>
        <nav class="nav">
          <a href="/" class="nav-link">Home</a>
          <a href="/privacy" class="nav-link">Privacy</a>
          <a href="/terms" class="nav-link">Terms</a>
        </nav>
      </div>
    </header>

    <main class="policy">
      <div class="container policy-content">
        <div class="section-header policy-header">
          <span class="section-label">Account</span>
          <h1 class="section-title policy-title">Account Deletion Request</h1>
          <p class="section-description">
            Enter the email address tied to your account. We'll store your
            request and follow up shortly.
          </p>
        </div>

        <section class="policy-section" style="max-width: 520px;">
          <form id="deletion-form" class="deletion-form">
            <label class="policy-section" style="padding: 0; border-top: none;">
              <span style="display:block; font-size: 12px; color: var(--text-secondary); margin-bottom: 8px;">Email address</span>
              <input
                type="email"
                name="email"
                placeholder="name@example.com"
                required
                autocomplete="email"
                style="width: 100%; padding: 12px 14px; border-radius: 4px; border: 1px solid var(--border); background: var(--bg-card); color: var(--text-primary); font-family: inherit;"
              />
            </label>
            <button
              type="submit"
              class="btn btn-primary"
              style="margin-top: 16px; width: 100%; justify-content: center;"
            >
              Submit request
            </button>
            <p id="deletion-message" style="margin-top: 12px; font-size: 13px; color: var(--text-secondary);"></p>
          </form>
        </section>
      </div>
    </main>

    <footer class="footer">
      <div class="container footer-content">
        <p class="footer-text">© 2024 moCODE. Built for developers.</p>
        <div class="footer-links">
          <a href="/privacy" class="footer-link">Privacy</a>
          <a href="/terms" class="footer-link">Terms</a>
        </div>
      </div>
    </footer>

    <script>
      const form = document.getElementById('deletion-form');
      const message = document.getElementById('deletion-message');

      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        message.textContent = '';
        const formData = new FormData(form);
        const email = String(formData.get('email') || '').trim();
        if (!email) {
          message.textContent = 'Please enter a valid email address.';
          return;
        }

        try {
          const response = await fetch('/api/v1/account-deletion-request', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email }),
          });
          if (!response.ok) {
            const data = await response.json().catch(() => ({}));
            message.textContent = data.error || 'Failed to submit request.';
            return;
          }
          form.reset();
          message.textContent = 'Request submitted. We will follow up shortly.';
        } catch (error) {
          message.textContent = 'Network error. Please try again.';
        }
      });
    </script>
  </body>
</html>`,
  );
});


app.get("/api/health", (c) => c.json({ ok: true, service: "mecode-server" }));

app.get("/billing/complete", (c) => c.html(billingCompleteHtml));

app.post("/api/v1/billing/webhook", async (c) => {
  const rawBody = await c.req.text();
  const webhookHeaders = {
    "webhook-id": c.req.header("webhook-id") ?? "",
    "webhook-signature": c.req.header("webhook-signature") ?? "",
    "webhook-timestamp": c.req.header("webhook-timestamp") ?? "",
  };

  try {
    await webhookVerifier.verify(rawBody, webhookHeaders);
  } catch {
    return c.json({ error: "Invalid webhook signature" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    return c.json({ error: "Invalid webhook payload" }, 400);
  }

  const eventType =
    (payload.type as string | undefined) ??
    (payload.event_type as string | undefined) ??
    (payload.event as string | undefined);

  if (eventType !== "payment.succeeded") {
    return c.json({ received: true, ignored: eventType ?? "unknown" });
  }

  const data = (payload.data as Record<string, unknown> | undefined) ?? payload;
  const metadata = (data.metadata as Record<string, string> | undefined) ?? {};

  const userId = metadata.user_id;
  const checkoutSessionId =
    (data.checkout_session_id as string | undefined) ??
    (data.session_id as string | undefined);
  const paymentId =
    (data.payment_id as string | undefined) ??
    (data.id as string | undefined) ??
    null;

  let resolvedUserId = userId ?? null;

  if (!resolvedUserId && checkoutSessionId) {
    const existing = await db
      .select({ userId: checkoutSessions.userId })
      .from(checkoutSessions)
      .where(eq(checkoutSessions.dodoSessionId, checkoutSessionId))
      .limit(1);
    resolvedUserId = existing[0]?.userId ?? null;
  }

  if (!resolvedUserId) {
    return c.json({ received: true, ignored: "missing-user-id" });
  }

  await db
    .insert(entitlements)
    .values({
      userId: resolvedUserId,
      oneTimeUnlocked: true,
      paymentId,
      provider: "dodopayments",
      paidAt: new Date(),
    })
    .onConflictDoUpdate({
      target: entitlements.userId,
      set: {
        oneTimeUnlocked: true,
        paymentId,
        provider: "dodopayments",
        paidAt: new Date(),
        updatedAt: new Date(),
      },
    });

  if (checkoutSessionId) {
    await db
      .update(checkoutSessions)
      .set({
        status: "paid",
        paymentId,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(checkoutSessions.userId, resolvedUserId),
          eq(checkoutSessions.dodoSessionId, checkoutSessionId),
        ),
      );
  }

  return c.json({ received: true });
});

app.use("/api/v1/*", firebaseAuthMiddleware);

app.get("/api/v1/auth/me", async (c) => {
  const user = c.get("authUser");

  const entitlement = await db
    .select({
      oneTimeUnlocked: entitlements.oneTimeUnlocked,
      paidAt: entitlements.paidAt,
    })
    .from(entitlements)
    .where(eq(entitlements.userId, user.id))
    .limit(1);

  return c.json({
    user,
    // access: {
    //   oneTimeUnlocked: entitlement[0]?.oneTimeUnlocked ?? false,
    //   paidAt: entitlement[0]?.paidAt ?? null,
    // },
    access: {
      oneTimeUnlocked: true,
      paidAt: new Date(),
    },
  });
});

app.get("/api/v1/billing/status", async (c) => {
  const user = c.get("authUser");

  const entitlement = await db
    .select({
      oneTimeUnlocked: entitlements.oneTimeUnlocked,
      provider: entitlements.provider,
      paymentId: entitlements.paymentId,
      paidAt: entitlements.paidAt,
    })
    .from(entitlements)
    .where(eq(entitlements.userId, user.id))
    .limit(1);

  // return c.json({
  //   oneTimeUnlocked: entitlement[0]?.oneTimeUnlocked ?? false,
  //   provider: entitlement[0]?.provider ?? null,
  //   paymentId: entitlement[0]?.paymentId ?? null,
  //   paidAt: entitlement[0]?.paidAt ?? null,
  // });

  return c.json({
    oneTimeUnlocked: true,
    provider: "dodopayments",
    paymentId: "wieuriw",
    paidAt: new Date(),
  });
});

app.post("/api/v1/billing/create-checkout-session", async (c) => {
  const user = c.get("authUser");
  const body = await c.req.json().catch(() => ({}));
  const input = createCheckoutSchema.safeParse(body);

  if (!input.success) {
    return c.json(
      { error: "Invalid payload", details: input.error.flatten() },
      400,
    );
  }

  const existingEntitlement = await db
    .select({ oneTimeUnlocked: entitlements.oneTimeUnlocked })
    .from(entitlements)
    .where(eq(entitlements.userId, user.id))
    .limit(1);

  if (existingEntitlement[0]?.oneTimeUnlocked) {
    return c.json({ error: "One-time access already unlocked" }, 409);
  }

  const resolvedProductId = env.DODO_DEFAULT_PRODUCT_ID;
  const sessionTtlMs = env.CHECKOUT_SESSION_TTL_MINUTES * 60 * 1000;
  const activeSessionCutoff = new Date(Date.now() - sessionTtlMs);

  const activeSession = await db
    .select({
      dodoSessionId: checkoutSessions.dodoSessionId,
      checkoutUrl: checkoutSessions.checkoutUrl,
    })
    .from(checkoutSessions)
    .where(
      and(
        eq(checkoutSessions.userId, user.id),
        eq(checkoutSessions.productId, resolvedProductId),
        eq(checkoutSessions.quantity, input.data.quantity),
        eq(checkoutSessions.status, "created"),
        gte(checkoutSessions.createdAt, activeSessionCutoff),
      ),
    )
    .orderBy(desc(checkoutSessions.createdAt))
    .limit(1);

  const reusableSession = activeSession[0];
  if (reusableSession) {
    return c.json({
      sessionId: reusableSession.dodoSessionId,
      checkoutUrl: reusableSession.checkoutUrl,
      reused: true,
    });
  }

  const session = await createDodoCheckoutSession({
    productId: resolvedProductId,
    quantity: input.data.quantity,
    customerEmail: user.email,
    customerName: user.displayName,
    returnUrl: `${env.APP_BASE_URL}/billing/complete`,
    metadata: {
      user_id: user.id,
      firebase_uid: user.firebaseUid,
    },
  });

  await db.insert(checkoutSessions).values({
    userId: user.id,
    dodoSessionId: session.session_id,
    checkoutUrl: session.checkout_url,
    productId: resolvedProductId,
    quantity: input.data.quantity,
    status: "created",
  });

  return c.json({
    sessionId: session.session_id,
    checkoutUrl: session.checkout_url,
    reused: false,
  });
});

app.post("/api/v1/account-deletion-request", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const input = accountDeletionSchema.safeParse(body);

  if (!input.success) {
    return c.json(
      { error: "Invalid payload", details: input.error.flatten() },
      400,
    );
  }

  await db.insert(accountDeletionRequests).values({
    email: input.data.email,
  });

  return c.json({ ok: true });
});

export default app;
