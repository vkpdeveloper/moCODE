import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  DODO_PAYMENTS_API_KEY: z.string().min(1),
  DODO_WEBHOOK_SECRET: z.string().min(1),
  DODO_ENVIRONMENT: z.enum(["test_mode", "live_mode"]).default("test_mode"),
  DODO_DEFAULT_PRODUCT_ID: z.string().min(1),
  CHECKOUT_SESSION_TTL_MINUTES: z.coerce.number().int().positive().default(30),
  APP_BASE_URL: z.string().url().default("http://localhost:3000"),
  FIREBASE_PROJECT_ID: z.string().min(1),
  FIREBASE_CLIENT_EMAIL: z.string().min(1),
  FIREBASE_PRIVATE_KEY: z.string().min(1),
  CORS_ORIGINS: z.string().optional(),
  PORT: z.coerce.number().int().positive().default(3000),
  RESEND_API_KEY: z.string().min(1),
  MY_EMAIL: z.string().email(),
});

const parsedEnv = envSchema.safeParse(process.env);

if (!parsedEnv.success) {
  const missingOrInvalid = Object.entries(parsedEnv.error.flatten().fieldErrors)
    .filter(([, messages]) => messages && messages.length > 0)
    .map(([key, messages]) => `${key}: ${messages?.join(", ")}`)
    .join("\n");

  throw new Error(`Invalid environment variables:\n${missingOrInvalid}`);
}

export const env = parsedEnv.data;

export const dodoApiBaseUrl =
  env.DODO_ENVIRONMENT === "live_mode"
    ? "https://live.dodopayments.com"
    : "https://test.dodopayments.com";

export const corsOrigins = env.CORS_ORIGINS?.split(",")
  .map((origin) => origin.trim())
  .filter(Boolean) ?? ["*"];
