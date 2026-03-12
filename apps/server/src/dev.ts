import "dotenv/config";

import { serve } from "@hono/node-server";

import server from "./index";
import { env } from "./lib/env";
import { logInfo } from "./lib/logging";

const port = env.PORT;

serve(
  {
    fetch: server.fetch,
    port,
  },
  (info) => {
    logInfo(`mecode-server listening on http://localhost:${info.port}`);
  },
);
