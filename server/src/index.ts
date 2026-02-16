import { and, desc, eq, gte } from "drizzle-orm";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { readFile, readdir, stat } from "node:fs/promises";
import { access, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { Webhook } from "standardwebhooks";
import { z } from "zod";

import { db } from "./db/client";
import { checkoutSessions, entitlements } from "./db/schema";
import { corsOrigins, env } from "./lib/env";
import { createDodoCheckoutSession } from "./lib/dodo";
import { firebaseAuthMiddleware } from "./middleware/firebase-auth";
import { renderLandingPage } from "./landing/LandingPage";
import { renderPrivacyPage } from "./landing/PrivacyPage";
import { renderTermsPage } from "./landing/TermsPage";

type Variables = {
  authUser: {
    id: string;
    firebaseUid: string;
    email: string;
    displayName: string | null;
  };
};

const webhookVerifier = new Webhook(env.DODO_WEBHOOK_SECRET);
const billingCompleteHtml = readFileSync(
  fileURLToPath(new URL("./views/billing-complete.html", import.meta.url)),
  "utf8",
);

const createCheckoutSchema = z.object({
  quantity: z.number().int().min(1).max(10).default(1),
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

const IMAGES_DIR = join(process.cwd(), "..", "images");
const ASSETS_DIR = join(process.cwd(), "..", "assets");

app.get("/", async (c) => {
  return renderLandingPage();
});

app.get("/privacy", async () => {
  return renderPrivacyPage();
});

app.get("/terms", async () => {
  return renderTermsPage();
});

app.get("/images/:filename", async (c) => {
  const filename = c.req.param("filename");
  const filepath = join(IMAGES_DIR, filename);
  
  try {
    await stat(filepath);
  } catch {
    return c.notFound();
  }
  
  const ext = filename.split(".").pop()?.toLowerCase();
  const contentTypes: Record<string, string> = {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
  };
  
  const contentType = contentTypes[ext ?? ""] ?? "application/octet-stream";
  const file = await readFile(filepath);
  
  return c.body(file, {
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=86400",
    },
  });
});

app.get("/app-icon.png", async (c) => {
  const filepath = join(ASSETS_DIR, "app_icon.png");
  
  try {
    await stat(filepath);
  } catch {
    return c.notFound();
  }
  
  const file = await readFile(filepath);
  
  return c.body(file, {
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=86400",
    },
  });
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

export default app;
