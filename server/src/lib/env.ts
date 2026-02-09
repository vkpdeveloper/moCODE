import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  DODO_PAYMENTS_API_KEY: z.string().min(1),
  DODO_WEBHOOK_SECRET: z.string().min(1),
  DODO_ENVIRONMENT: z.enum(['test_mode', 'live_mode']).default('test_mode'),
  DODO_DEFAULT_PRODUCT_ID: z.string().min(1),
  APP_BASE_URL: z.string().url().default('http://localhost:3000'),
  FIREBASE_PROJECT_ID: z.string().min(1),
  FIREBASE_CLIENT_EMAIL: z.string().min(1),
  FIREBASE_PRIVATE_KEY: z.string().min(1),
  CORS_ORIGINS: z.string().optional(),
});

export const env = envSchema.parse(process.env);

export const dodoApiBaseUrl =
  env.DODO_ENVIRONMENT === 'live_mode'
    ? 'https://live.dodopayments.com'
    : 'https://test.dodopayments.com';

export const corsOrigins =
  env.CORS_ORIGINS?.split(',').map((origin) => origin.trim()).filter(Boolean) ?? ['*'];
