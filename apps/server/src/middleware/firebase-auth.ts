import { eq } from 'drizzle-orm';
import { createMiddleware } from 'hono/factory';

import { db } from '../db/client';
import { users } from '../db/schema';
import { firebaseAuth } from '../lib/firebase-admin';

type AuthUser = {
  id: string;
  firebaseUid: string;
  email: string;
  displayName: string | null;
};

type Variables = {
  authUser: AuthUser;
};

export const firebaseAuthMiddleware = createMiddleware<{ Variables: Variables }>(
  async (c, next) => {
    const authHeader = c.req.header('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Missing bearer token' }, 401);
    }

    const idToken = authHeader.slice('Bearer '.length).trim();

    try {
      const decoded = await firebaseAuth.verifyIdToken(idToken);
      const email = decoded.email;
      if (!email) {
        return c.json({ error: 'Firebase token missing email' }, 401);
      }

      const upserted = await db
        .insert(users)
        .values({
          firebaseUid: decoded.uid,
          email,
          displayName: decoded.name ?? null,
        })
        .onConflictDoUpdate({
          target: users.firebaseUid,
          set: {
            email,
            displayName: decoded.name ?? null,
            updatedAt: new Date(),
          },
        })
        .returning({
          id: users.id,
          firebaseUid: users.firebaseUid,
          email: users.email,
          displayName: users.displayName,
        });

      const authUser = upserted[0];
      if (!authUser) {
        const fallback = await db
          .select({
            id: users.id,
            firebaseUid: users.firebaseUid,
            email: users.email,
            displayName: users.displayName,
          })
          .from(users)
          .where(eq(users.firebaseUid, decoded.uid))
          .limit(1);

        if (!fallback[0]) {
          return c.json({ error: 'Unable to load authenticated user' }, 500);
        }

        c.set('authUser', fallback[0]);
        await next();
        return;
      }

      c.set('authUser', authUser);
      await next();
    } catch {
      return c.json({ error: 'Invalid Firebase token' }, 401);
    }
  },
);
