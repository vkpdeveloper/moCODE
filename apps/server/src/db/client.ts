import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import { env } from '../lib/env';

const queryClient = postgres(env.DATABASE_URL, {
  max: 5,
  idle_timeout: 20,
  connect_timeout: 10,
});

export const db = drizzle(queryClient);
