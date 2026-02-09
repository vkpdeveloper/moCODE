import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

import { env } from './env';

const privateKey = env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n');

const app = getApps()[0]
  ? getApps()[0]
  : initializeApp({
      credential: cert({
        projectId: env.FIREBASE_PROJECT_ID,
        clientEmail: env.FIREBASE_CLIENT_EMAIL,
        privateKey,
      }),
    });

export const firebaseAuth = getAuth(app);
