import 'dotenv/config';

import { serve } from '@hono/node-server';

import server from './app';
import { env } from './lib/env';

const port = env.PORT;

serve(
  {
    fetch: server.fetch,
    port,
  },
  (info) => {
    console.log(`mecode-server listening on http://localhost:${info.port}`);
  },
);
