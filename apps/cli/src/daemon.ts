import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import type { Dirent } from "node:fs";
import { readdir, readFile, stat } from "node:fs/promises";
import { homedir, hostname, platform } from "node:os";
import { basename, isAbsolute, join, relative, resolve } from "node:path";

import type * as acp from "@agentclientprotocol/sdk";
import { z } from "zod";

import { syncAgentCatalog } from "./agents";
import { AgentRuntimeManager } from "./acp-runtime";
import { enrichAgentDescriptorsFromRegistry } from "./agent-registry";
import { StateDatabase } from "./db";
import { getLogger, sanitizeLogValue, serializeError } from "./logger";
import { buildOpenApiSpec, createApiDocsHtml } from "./openapi";
import { getStatePaths } from "./paths";
import {
  latestDiffsFromEntries,
  latestTodosFromEntries,
} from "./session-derived-state";
import type {
  BroadcastEvent,
  JsonObject,
  JsonValue,
  ProjectRecord,
  SessionRecord,
} from "./types";

const pairingRedeemSchema = z.object({
  code: z.string().trim().min(6),
  deviceName: z.string().trim().min(1).max(120),
});

const openProjectSchema = z.object({
  path: z.string().trim().min(1),
});

const updateProjectSchema = z.object({
  displayName: z.string().trim().min(1).max(120).nullable().optional(),
  preferredAgentId: z.string().trim().min(1).max(120).nullable().optional(),
});

const createSessionSchema = z.object({
  projectId: z.string().trim().min(1),
  agentId: z.string().trim().min(1),
});

const updateSessionSchema = z.object({
  title: z.string().trim().min(1).max(240).nullable().optional(),
});

const promptContentBlockSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("text"),
    text: z.string().trim().min(1),
  }),
  z.object({
    type: z.literal("resource_link"),
    uri: z.string().trim().min(1),
    name: z.string().trim().min(1),
    title: z.string().trim().min(1).nullable().optional(),
    description: z.string().trim().min(1).nullable().optional(),
    mimeType: z.string().trim().min(1).nullable().optional(),
    size: z.number().int().nonnegative().nullable().optional(),
  }),
]);

const promptSessionSchema = z
  .object({
    text: z.string().trim().min(1).optional(),
    prompt: z.array(promptContentBlockSchema).min(1).optional(),
  })
  .refine((value) => value.text || value.prompt, {
    message: "Either text or prompt is required.",
    path: ["text"],
  });

const setSessionModeSchema = z.object({
  modeId: z.string().trim().min(1),
});

const setSessionConfigOptionSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("boolean"),
    configId: z.string().trim().min(1),
    value: z.boolean(),
  }),
  z.object({
    type: z.literal("value"),
    configId: z.string().trim().min(1),
    value: z.string().trim().min(1),
  }),
]);

const replyPermissionSchema = z.object({
  reply: z.enum(["once", "always", "reject"]),
});

const questionAnswerSchema = z.array(z.string());

const replyQuestionSchema = z.discriminatedUnion("outcome", [
  z.object({
    outcome: z.literal("cancelled"),
  }),
  z.object({
    outcome: z.literal("answered"),
    answers: z.record(z.string(), questionAnswerSchema),
  }),
]);

const wsMessageSchema = z.discriminatedUnion("type", [
  z.object({
    requestId: z.string().optional(),
    type: z.literal("subscribe_session"),
    sessionId: z.string(),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("create_session"),
    projectId: z.string(),
    agentId: z.string(),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("load_session"),
    sessionId: z.string(),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("prompt_session"),
    sessionId: z.string(),
    text: z.string().min(1).optional(),
    prompt: z.array(promptContentBlockSchema).min(1).optional(),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("cancel_session"),
    sessionId: z.string(),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("reply_permission"),
    sessionId: z.string(),
    permissionRequestId: z.string(),
    outcome: z.discriminatedUnion("outcome", [
      z.object({
        outcome: z.literal("cancelled"),
      }),
      z.object({
        outcome: z.literal("selected"),
        optionId: z.string(),
      }),
    ]),
  }),
  z.object({
    requestId: z.string().optional(),
    type: z.literal("reply_question"),
    sessionId: z.string(),
    questionRequestId: z.string(),
    outcome: replyQuestionSchema,
  }),
]);

type PairingCode = {
  code: string;
  createdAt: number;
  expiresAt: number;
};

type SocketData = {
  deviceId: string;
  subscriptions: Set<string>;
};

type SseClient = {
  deviceId: string;
  subscriptions: Set<string>;
  send: (event: BroadcastEvent) => void;
  close: () => void;
};

type PendingPermissionRecord = {
  id: string;
  sessionId: string;
  request: JsonObject;
  createdAt: number;
};

type PendingQuestionRecord = {
  id: string;
  sessionId: string;
  request: JsonObject;
  createdAt: number;
};

type ResourceSearchItem = {
  absolute: string;
  extension: string | null;
  name: string;
  path: string;
  score: number;
  type: "file";
};

type ResourceIndexCacheEntry = {
  expiresAt: number;
  files: string[];
};

const IGNORE_DIRS = new Set([
  ".cache",
  ".DS_Store",
  ".dart_tool",
  ".git",
  ".next",
  ".pnpm-store",
  "build",
  "dist",
  "Library",
  "Movies",
  "Music",
  "Pictures",
  "node_modules",
  "tmp",
  "vendor",
]);

const RESOURCE_INDEX_TTL_MS = 3_000;
const resourceIndexCache = new Map<string, ResourceIndexCacheEntry>();

function json(data: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "content-type, authorization",
      "access-control-allow-methods": "GET, POST, PATCH, DELETE, OPTIONS",
      ...(init.headers ?? {}),
    },
  });
}

function html(body: string, init: ResponseInit = {}) {
  return new Response(body, {
    ...init,
    headers: {
      "content-type": "text/html; charset=utf-8",
      ...(init.headers ?? {}),
    },
  });
}

function formatZodPath(path: PropertyKey[]) {
  if (path.length === 0) {
    return "body";
  }
  return `body.${path.map(String).join(".")}`;
}

const daemonLogger = getLogger("daemon");

function handleRequestError(error: unknown) {
  if (error instanceof z.ZodError) {
    return json(
      {
        error: "Invalid request.",
        issues: error.issues.map((issue) => ({
          path: formatZodPath(issue.path),
          message: issue.message,
        })),
      },
      { status: 400 },
    );
  }

  if (error instanceof SyntaxError) {
    return json({ error: "Request body must be valid JSON." }, { status: 400 });
  }

  if (
    error &&
    typeof error === "object" &&
    "code" in error &&
    error.code === "ENOENT"
  ) {
    return json({ error: "Requested path was not found." }, { status: 404 });
  }

  daemonLogger.error("request failed with internal error", {
    error: serializeError(error),
  });
  return json({ error: "Internal server error." }, { status: 500 });
}

function generatePairingCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function serializeProject(project: ProjectRecord, db: StateDatabase) {
  return {
    ...project,
    name: project.displayName ?? project.detectedName,
    sessionCount: db.listSessions(project.id).length,
  };
}

function isLikelyProjectDir(path: string, names: string[]) {
  const markers = new Set([
    ".git",
    "package.json",
    "pyproject.toml",
    "Cargo.toml",
    "go.mod",
    "Gemfile",
    "composer.json",
  ]);
  return names.some((name) => markers.has(name));
}

async function searchProjectDirectories(query: string, limit = 50) {
  const results: string[] = [];
  const queue = [process.env.HOME || Bun.env.HOME || process.cwd()];
  const normalizedQuery = query.trim().toLowerCase();

  while (queue.length > 0 && results.length < limit) {
    const current = queue.shift();
    if (!current) {
      continue;
    }

    let dirEntries: Dirent<string>[];
    try {
      dirEntries = await readdir(current, {
        withFileTypes: true,
        encoding: "utf8",
      });
    } catch {
      continue;
    }

    const names = dirEntries.map((entry) => entry.name);
    const currentMatches =
      normalizedQuery.length === 0 ||
      current.toLowerCase().includes(normalizedQuery) ||
      names.some((name) => name.toLowerCase().includes(normalizedQuery));

    if (currentMatches && isLikelyProjectDir(current, names)) {
      results.push(current);
      continue;
    }

    for (const entry of dirEntries) {
      if (!entry.isDirectory()) {
        continue;
      }
      if (entry.name.startsWith(".") || IGNORE_DIRS.has(entry.name)) {
        continue;
      }
      queue.push(join(current, entry.name));
    }
  }

  return results;
}

function sendWs(
  socket: Bun.ServerWebSocket<SocketData>,
  event: BroadcastEvent,
) {
  socket.send(JSON.stringify(event));
}

function sendWsRequestError(
  socket: Bun.ServerWebSocket<SocketData>,
  requestId: string | null | undefined,
  error: string,
) {
  sendWs(socket, {
    type: "request_error",
    payload: {
      requestId: requestId ?? null,
      error,
    },
  });
}

function broadcastSessionEvent(
  wsClients: Map<Bun.ServerWebSocket<SocketData>, SocketData>,
  sseClients: Set<SseClient>,
  sessionId: string,
  event: BroadcastEvent,
) {
  for (const [socket, data] of wsClients.entries()) {
    if (!data.subscriptions.has(sessionId)) {
      continue;
    }
    sendWs(socket, event);
  }

  for (const client of sseClients) {
    if (!client.subscriptions.has(sessionId)) {
      continue;
    }
    client.send(event);
  }
}

function authenticateRequest(request: Request, db: StateDatabase) {
  const authHeader = request.headers.get("authorization");
  const token = authHeader?.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length)
    : null;

  if (!token) {
    return {
      ok: false as const,
      response: json({ error: "Missing bearer token." }, { status: 401 }),
    };
  }

  const device = db.getPairedDeviceByToken(token);
  if (!device) {
    return {
      ok: false as const,
      response: json({ error: "Invalid bearer token." }, { status: 401 }),
    };
  }

  db.touchPairedDevice(device.id);
  return {
    ok: true as const,
    device,
  };
}

function isLoopbackRequest(request: Request) {
  const url = new URL(request.url);
  return url.hostname === "127.0.0.1" || url.hostname === "localhost";
}

async function listDirectoryNodes(path: string, directory: string | null) {
  const root = directory ? resolve(directory) : homedir();
  const target = path
    ? isAbsolute(path)
      ? resolve(path)
      : resolve(root, path)
    : root;
  const entries = await readdir(target, {
    withFileTypes: true,
    encoding: "utf8",
  });

  return entries
    .filter((entry) => !entry.name.startsWith("."))
    .map((entry) => ({
      name: entry.name,
      path: relative(root, resolve(target, entry.name)),
      absolute: resolve(target, entry.name),
      type: entry.isDirectory() ? "directory" : "file",
      ignored: IGNORE_DIRS.has(entry.name),
    }))
    .sort((left, right) => {
      if (left.type !== right.type) {
        return left.type === "directory" ? -1 : 1;
      }
      return left.name.localeCompare(right.name);
    });
}

async function searchFiles(input: {
  query: string;
  type: string | null;
  directory: string | null;
  limit: number;
}) {
  const results: string[] = [];
  const root = input.directory ? resolve(input.directory) : homedir();
  const queue = [root];
  const query = input.query.trim().toLowerCase();

  while (queue.length > 0 && results.length < input.limit) {
    const current = queue.shift();
    if (!current) {
      continue;
    }

    let entries: Dirent<string>[];
    try {
      entries = await readdir(current, {
        withFileTypes: true,
        encoding: "utf8",
      });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (entry.name.startsWith(".") || IGNORE_DIRS.has(entry.name)) {
        continue;
      }

      const absolute = resolve(current, entry.name);
      if (entry.isDirectory()) {
        queue.push(absolute);
      }

      const type = entry.isDirectory() ? "directory" : "file";
      if (input.type && type !== input.type) {
        continue;
      }

      if (
        query.length === 0 ||
        entry.name.toLowerCase().includes(query) ||
        absolute.toLowerCase().includes(query)
      ) {
        results.push(absolute);
        if (results.length >= input.limit) {
          break;
        }
      }
    }
  }

  return results;
}

function normalizeSearchText(value: string) {
  return value.trim().toLowerCase();
}

function subsequenceScore(text: string, query: string) {
  if (!query) {
    return 0;
  }

  let score = 0;
  let queryIndex = 0;
  let streak = 0;

  for (let textIndex = 0; textIndex < text.length; textIndex += 1) {
    if (queryIndex >= query.length) {
      break;
    }

    if (text[textIndex] !== query[queryIndex]) {
      streak = 0;
      continue;
    }

    streak += 1;
    score += 2 + streak;
    queryIndex += 1;
  }

  return queryIndex === query.length ? score : 0;
}

function scoreResourceMatch(relativePath: string, query: string) {
  const normalizedQuery = normalizeSearchText(query);
  if (normalizedQuery.length === 0) {
    return 1;
  }

  const normalizedPath = normalizeSearchText(relativePath);
  const segments = normalizedPath.split("/");
  const fileName = segments.at(-1) ?? normalizedPath;

  if (fileName === normalizedQuery) {
    return 1_000;
  }

  if (fileName.startsWith(normalizedQuery)) {
    return 800 - Math.min(fileName.length - normalizedQuery.length, 50);
  }

  if (fileName.includes(normalizedQuery)) {
    return 700 - Math.min(fileName.indexOf(normalizedQuery), 100);
  }

  if (normalizedPath.startsWith(normalizedQuery)) {
    return 650 - Math.min(normalizedPath.length - normalizedQuery.length, 100);
  }

  if (normalizedPath.includes(normalizedQuery)) {
    return 500 - Math.min(normalizedPath.indexOf(normalizedQuery), 200);
  }

  const fuzzyFileScore = subsequenceScore(fileName, normalizedQuery);
  if (fuzzyFileScore > 0) {
    return 300 + fuzzyFileScore;
  }

  const fuzzyPathScore = subsequenceScore(normalizedPath, normalizedQuery);
  if (fuzzyPathScore > 0) {
    return 150 + fuzzyPathScore;
  }

  return 0;
}

function listIndexedFiles(root: string) {
  const cached = resourceIndexCache.get(root);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.files;
  }

  const globArgs = [
    "!**/.cache/**",
    "!**/.dart_tool/**",
    "!**/.git/**",
    "!**/.next/**",
    "!**/.pnpm-store/**",
    "!**/build/**",
    "!**/dist/**",
    "!**/node_modules/**",
    "!**/tmp/**",
    "!**/vendor/**",
  ];
  const args = ["--files", "--hidden", "--follow", "--color", "never"];
  for (const glob of globArgs) {
    args.push("--glob", glob);
  }

  const result = spawnSync("rg", args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });

  if (result.status !== 0) {
    return null;
  }

  const files = result.stdout
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

  resourceIndexCache.set(root, {
    expiresAt: Date.now() + RESOURCE_INDEX_TTL_MS,
    files,
  });

  return files;
}

async function searchResources(input: {
  directory: string | null;
  limit: number;
  query: string;
}) {
  const root = input.directory ? resolve(input.directory) : homedir();
  const limit = Number.isFinite(input.limit)
    ? Math.max(1, Math.min(Math.trunc(input.limit), 200))
    : 50;
  const indexed = listIndexedFiles(root);

  const buildResource = (relativePath: string, score: number): ResourceSearchItem => {
    const absolute = resolve(root, relativePath);
    const slashIndex = relativePath.lastIndexOf("/");
    const name = slashIndex === -1 ? relativePath : relativePath.slice(slashIndex + 1);
    const dotIndex = name.lastIndexOf(".");
    return {
      absolute,
      extension:
        dotIndex > 0 && dotIndex < name.length - 1 ? name.slice(dotIndex + 1).toLowerCase() : null,
      name,
      path: relativePath,
      score,
      type: "file",
    };
  };

  if (indexed) {
    const matches = indexed
      .map((relativePath) => ({
        relativePath,
        score: scoreResourceMatch(relativePath, input.query),
      }))
      .filter((entry) => entry.score > 0)
      .sort((left, right) => {
        if (left.score !== right.score) {
          return right.score - left.score;
        }
        return left.relativePath.localeCompare(right.relativePath);
      })
      .slice(0, limit)
      .map((entry) => buildResource(entry.relativePath, entry.score));

    return {
      resources: matches,
      root,
    };
  }

  const fallbackResults = await searchFiles({
    directory: root,
    limit,
    query: input.query,
    type: "file",
  });
  const resources = fallbackResults.map((absolute) =>
    buildResource(relative(root, absolute), scoreResourceMatch(relative(root, absolute), input.query)),
  );

  return {
    resources,
    root,
  };
}

function getGitBranch(directory: string | null) {
  if (!directory) {
    return "";
  }
  const result = spawnSync(
    "git",
    ["-C", directory, "branch", "--show-current"],
    {
      encoding: "utf8",
    },
  );
  return result.status === 0 ? result.stdout.trim() : "";
}

async function getDeviceModel() {
  if (process.platform === "darwin") {
    const model = spawnSync("sysctl", ["-n", "hw.model"], {
      encoding: "utf8",
    });
    return model.status === 0 ? model.stdout.trim() : null;
  }

  if (process.platform === "linux") {
    const vendor = await readFile(
      "/sys/devices/virtual/dmi/id/sys_vendor",
      "utf8",
    )
      .then((value) => value.trim())
      .catch(() => "");
    const product = await readFile(
      "/sys/devices/virtual/dmi/id/product_name",
      "utf8",
    )
      .then((value) => value.trim())
      .catch(() => "");
    const model = [vendor, product]
      .filter((value) => value.length > 0)
      .join(" ");
    return model.length === 0 ? null : model;
  }

  if (process.platform === "win32") {
    const result = spawnSync(
      "powershell",
      [
        "-NoProfile",
        "-Command",
        "(Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty Model)",
      ],
      { encoding: "utf8" },
    );
    return result.status === 0 ? result.stdout.trim() : null;
  }

  return null;
}

function getPathInfo(
  paths: ReturnType<typeof getStatePaths>,
  directory: string | null,
) {
  const root = directory ? resolve(directory) : homedir();
  return {
    home: homedir(),
    state: paths.stateDir,
    config: paths.configDir,
    worktree: root,
    directory: root,
  };
}

function normalizeLegacyPermissionReply(
  reply: string,
  record: PendingPermissionRecord | null,
) {
  const options = Array.isArray(record?.request.options)
    ? (record.request.options as JsonValue[])
    : ([] as JsonValue[]);
  const objects = options
    .map((option: JsonValue) =>
      option && typeof option === "object" && !Array.isArray(option)
        ? (option as JsonObject)
        : null,
    )
    .filter(
      (option: JsonObject | null): option is JsonObject => option !== null,
    );

  const desiredKind =
    reply === "always"
      ? "allow_always"
      : reply === "reject"
        ? "reject_once"
        : "allow_once";

  const selected = objects.find(
    (option: JsonObject) => option.kind === desiredKind,
  );
  if (!selected) {
    return reply === "reject"
      ? {
          outcome: {
            outcome: "cancelled" as const,
          },
        }
      : {
          outcome: {
            outcome: "selected" as const,
            optionId:
              typeof objects[0]?.optionId === "string"
                ? objects[0].optionId
                : "",
          },
        };
  }

  return {
    outcome: {
      outcome: "selected" as const,
      optionId: String(selected.optionId),
    },
  };
}

function serializePendingPermission(record: PendingPermissionRecord) {
  return {
    requestId: record.id,
    sessionId: record.sessionId,
    request: record.request,
    createdAt: record.createdAt,
  };
}

function serializePendingQuestion(record: PendingQuestionRecord) {
  return {
    requestId: record.id,
    sessionId: record.sessionId,
    request: record.request,
    createdAt: record.createdAt,
  };
}

export async function startDaemon(options: { port: number }) {
  const paths = getStatePaths();
  const logger = getLogger("daemon").child({ port: options.port });
  const deviceModel = await getDeviceModel();
  const db = new StateDatabase(paths.databasePath);
  const pairingCodes = new Map<string, PairingCode>();
  const wsClients = new Map<Bun.ServerWebSocket<SocketData>, SocketData>();
  const sseClients = new Set<SseClient>();
  const pendingPermissions = new Map<string, PendingPermissionRecord>();
  const pendingQuestions = new Map<string, PendingQuestionRecord>();
  const runtimeManager = new AgentRuntimeManager(
    db,
    paths,
    (sessionId, event) => {
      if (event.type === "permission_request") {
        const requestId =
          typeof event.payload.requestId === "string"
            ? event.payload.requestId
            : randomUUID();
        const request =
          event.payload.request &&
          typeof event.payload.request === "object" &&
          !Array.isArray(event.payload.request)
            ? (event.payload.request as JsonObject)
            : {};
        pendingPermissions.set(requestId, {
          id: requestId,
          sessionId,
          request,
          createdAt: Date.now(),
        });
      }
      if (event.type === "question_request") {
        const requestId =
          typeof event.payload.requestId === "string"
            ? event.payload.requestId
            : randomUUID();
        const request =
          event.payload.request &&
          typeof event.payload.request === "object" &&
          !Array.isArray(event.payload.request)
            ? (event.payload.request as JsonObject)
            : {};
        pendingQuestions.set(requestId, {
          id: requestId,
          sessionId,
          request,
          createdAt: Date.now(),
        });
      }
      logger.debug("broadcasting realtime event", {
        sessionId,
        eventType: event.type,
        payload: sanitizeLogValue(event.payload),
      });
      broadcastSessionEvent(wsClients, sseClients, sessionId, event);
    },
    logger.child({ component: "acp" }),
  );

  syncAgentCatalog(db, paths);
  logger.info("daemon starting", {
    port: options.port,
    deviceName: hostname(),
    deviceModel,
    platform: platform(),
    stateDir: paths.stateDir,
    logDir: paths.logDir,
  });

  const clearPendingPermissionsForSession = (sessionId: string) => {
    for (const [requestId, record] of pendingPermissions.entries()) {
      if (record.sessionId === sessionId) {
        pendingPermissions.delete(requestId);
      }
    }
  };

  const clearPendingQuestionsForSession = (sessionId: string) => {
    for (const [requestId, record] of pendingQuestions.entries()) {
      if (record.sessionId === sessionId) {
        pendingQuestions.delete(requestId);
      }
    }
  };

  const startBackgroundPrompt = async (
    sessionId: string,
    prompt: acp.ContentBlock[],
  ) => {
    const promptSummary = prompt
      .map((block) => {
        switch (block.type) {
          case "text":
            return block.text;
          case "resource_link":
            return [block.title, block.name, block.uri]
              .filter((value): value is string => typeof value === "string")
              .join(" ")
              .trim();
          default:
            return "";
        }
      })
      .filter((value) => value.trim().length > 0)
      .join("\n")
      .trim();
    logger.info("background prompt started", {
      sessionId,
      prompt: sanitizeLogValue(promptSummary),
    });
    try {
      await runtimeManager.promptSession(sessionId, prompt);
      logger.info("background prompt completed", {
        sessionId,
      });
    } catch (error) {
      logger.error("background prompt failed", {
        sessionId,
        error: serializeError(error),
      });
      throw error;
    } finally {
      const session = db.getSession(sessionId);
      if (session?.status === "idle") {
        clearPendingPermissionsForSession(sessionId);
        clearPendingQuestionsForSession(sessionId);
      }
    }
  };

  const server = Bun.serve<SocketData>({
    port: options.port,
    hostname: "0.0.0.0",
    idleTimeout: 60,
    fetch: async (request, serverInstance) => {
      try {
        const url = new URL(request.url);
        const pathname = url.pathname;
        const requestId = randomUUID();
        const requestLogger = logger.child({
          requestId,
          method: request.method,
          path: pathname,
        });
        requestLogger.info("incoming http request", {
          query: sanitizeLogValue(
            Object.fromEntries(url.searchParams.entries()),
          ),
          userAgent: request.headers.get("user-agent"),
        });
        const readLoggedJson = async (label: string) => {
          const body = ((await request.json()) as JsonObject) ?? {};
          requestLogger.info("parsed request body", {
            label,
            body: sanitizeLogValue(body),
          });
          return body;
        };

        if (request.method === "OPTIONS") {
          return json({});
        }

        if (
          pathname === "/api/openapi.json" &&
          ["GET", "HEAD"].includes(request.method)
        ) {
          return json(buildOpenApiSpec(options.port));
        }

        if (
          pathname === "/api/docs" &&
          ["GET", "HEAD"].includes(request.method)
        ) {
          return html(createApiDocsHtml("/api/openapi.json"));
        }

        if (pathname === "/v1/realtime") {
          const token = url.searchParams.get("token");
          if (!token) {
            requestLogger.warn("realtime upgrade rejected: missing token");
            return json({ error: "Missing token." }, { status: 401 });
          }
          const device = db.getPairedDeviceByToken(token);
          if (!device) {
            requestLogger.warn("realtime upgrade rejected: invalid token");
            return json({ error: "Invalid token." }, { status: 401 });
          }
          db.touchPairedDevice(device.id);
          const upgraded = serverInstance.upgrade(request, {
            data: {
              deviceId: device.id,
              subscriptions: new Set<string>(),
            },
          });
          requestLogger.info("realtime upgrade attempted", {
            deviceId: device.id,
            upgraded,
          });
          return upgraded
            ? undefined
            : json({ error: "WebSocket upgrade failed." }, { status: 400 });
        }

        if (pathname === "/v1/health" && request.method === "GET") {
          return json({
            healthy: true,
            version: "0.1.0",
            port: options.port,
            deviceName: hostname(),
            deviceModel,
            platform: platform(),
          });
        }

        if (pathname === "/v1/discovery" && request.method === "GET") {
          return json({
            deviceName: hostname(),
            deviceModel,
            platform: platform(),
            port: options.port,
            pairingRequired: true,
          });
        }

        if (pathname === "/v1/pairing/code" && request.method === "POST") {
          if (!isLoopbackRequest(request)) {
            requestLogger.warn("pairing code request rejected: non-loopback");
            return json(
              { error: "Pairing codes may only be created locally." },
              { status: 403 },
            );
          }
          const code = generatePairingCode();
          pairingCodes.set(code, {
            code,
            createdAt: Date.now(),
            expiresAt: Date.now() + 5 * 60 * 1000,
          });
          requestLogger.info("pairing code generated", {
            expiresInSeconds: 300,
          });
          return json({ code, expiresInSeconds: 300 });
        }

        if (
          pathname === "/v1/pairing/code/redeem" &&
          request.method === "POST"
        ) {
          const body = pairingRedeemSchema.parse(
            await readLoggedJson("pairingRedeem"),
          );
          const pairingCode = pairingCodes.get(body.code);
          if (!pairingCode || pairingCode.expiresAt < Date.now()) {
            requestLogger.warn("pairing code redemption failed", {
              code: body.code,
            });
            return json(
              { error: "Pairing code is invalid or expired." },
              { status: 400 },
            );
          }
          pairingCodes.delete(body.code);

          const rawToken = randomUUID();
          const { device } = db.createPairedDevice(body.deviceName, rawToken);
          requestLogger.info("pairing code redeemed", {
            deviceId: device.id,
            deviceName: device.name,
          });
          return json({
            token: rawToken,
            device: {
              id: device.id,
              name: device.name,
            },
          });
        }

        if (pathname.startsWith("/v1/")) {
          const auth = authenticateRequest(request, db);
          if (!auth.ok) {
            requestLogger.warn("authenticated route rejected", {
              status: auth.response.status,
            });
            return auth.response;
          }

          if (pathname === "/v1/agents" && request.method === "GET") {
            const agents = await enrichAgentDescriptorsFromRegistry(
              runtimeManager.listAgents(),
              paths,
              requestLogger,
            );

            return json({
              agents,
            });
          }

          if (pathname === "/v1/events" && request.method === "GET") {
            const encoder = new TextEncoder();
            const subscriptionValues = url.searchParams
              .getAll("sessionId")
              .flatMap((value) => value.split(","))
              .map((value) => value.trim())
              .filter((value) => value.length > 0);
            const subscriptions = new Set(subscriptionValues);
            let closeConnection = () => {};

            const stream = new ReadableStream<Uint8Array>({
              start(controller) {
                let closed = false;
                let keepAlive: ReturnType<typeof setInterval> | undefined;

                const close = () => {
                  if (closed) {
                    return;
                  }
                  closed = true;
                  if (keepAlive) {
                    clearInterval(keepAlive);
                    keepAlive = undefined;
                  }
                  sseClients.delete(client);
                  try {
                    controller.close();
                  } catch {}
                };

                const client: SseClient = {
                  deviceId: auth.device.id,
                  subscriptions,
                  send(event) {
                    if (closed) {
                      return;
                    }
                    try {
                      controller.enqueue(
                        encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
                      );
                    } catch {
                      close();
                    }
                  },
                  close,
                };

                closeConnection = close;
                sseClients.add(client);
                requestLogger.info("sse stream opened", {
                  deviceId: auth.device.id,
                  subscriptions: [...subscriptions],
                });

                controller.enqueue(encoder.encode("retry: 3000\n\n"));
                controller.enqueue(encoder.encode(": connected\n\n"));
                keepAlive = setInterval(() => {
                  if (closed) {
                    return;
                  }
                  try {
                    controller.enqueue(encoder.encode(": keepalive\n\n"));
                  } catch {
                    close();
                  }
                }, 15000);

                request.signal.addEventListener("abort", close);
              },
              cancel() {
                closeConnection();
              },
            });

            return new Response(stream, {
              headers: {
                "content-type": "text/event-stream; charset=utf-8",
                "cache-control": "no-cache, no-transform",
                connection: "keep-alive",
                "x-accel-buffering": "no",
                "access-control-allow-origin": "*",
                "access-control-allow-headers": "content-type, authorization",
                "access-control-allow-methods": "GET, OPTIONS",
              },
            });
          }

          if (
            pathname.match(/^\/v1\/agents\/[^/]+\/initialize$/) &&
            request.method === "POST"
          ) {
            const agentId = pathname.split("/")[3]!;
            const result = await runtimeManager.initializeAgent(agentId);
            return json(result);
          }

          if (
            pathname.match(/^\/v1\/agents\/[^/]+\/authenticate$/) &&
            request.method === "POST"
          ) {
            const agentId = pathname.split("/")[3]!;
            const payload = await readLoggedJson("authenticateAgent");
            const result = await runtimeManager.authenticateAgent(
              agentId,
              payload as never,
            );
            return json(result);
          }

          if (pathname === "/v1/projects" && request.method === "GET") {
            return json({
              projects: db
                .listProjects()
                .map((project) => serializeProject(project, db)),
            });
          }

          if (pathname === "/v1/projects/open" && request.method === "POST") {
            const body = openProjectSchema.parse(
              await readLoggedJson("openProject"),
            );
            const fullPath = resolve(body.path);
            const info = await stat(fullPath);
            if (!info.isDirectory()) {
              return json(
                { error: "Path must be a directory." },
                { status: 400 },
              );
            }

            const project = db.openProject(fullPath);
            return json({
              project: serializeProject(project, db),
              sessions: db.listSessions(project.id),
            });
          }

          if (pathname === "/v1/projects/search" && request.method === "GET") {
            const query = url.searchParams.get("q") ?? "";
            const known =
              query.trim().length > 0
                ? db.searchProjects(query)
                : db.listProjects();
            const discovered = await searchProjectDirectories(query, 50);
            return json({
              known: known.map((project) => serializeProject(project, db)),
              discovered,
            });
          }

          if (
            pathname.match(/^\/v1\/projects\/[^/]+$/) &&
            request.method === "GET"
          ) {
            const projectId = pathname.split("/")[3]!;
            const project = db.getProject(projectId);
            if (!project) {
              return json({ error: "Project not found." }, { status: 404 });
            }
            return json({
              project: serializeProject(project, db),
              sessions: db.listSessions(project.id),
            });
          }

          if (
            pathname.match(/^\/v1\/projects\/[^/]+$/) &&
            request.method === "PATCH"
          ) {
            const projectId = pathname.split("/")[3]!;
            const body = updateProjectSchema.parse(
              await readLoggedJson("updateProject"),
            );
            const project = db.updateProject(projectId, {
              displayName: body.displayName,
              preferredAgentId: body.preferredAgentId,
            });
            if (!project) {
              return json({ error: "Project not found." }, { status: 404 });
            }
            return json({
              project: serializeProject(project, db),
            });
          }

          if (pathname === "/v1/sessions" && request.method === "GET") {
            const projectId = url.searchParams.get("projectId") ?? undefined;
            const agentId = url.searchParams.get("agentId") ?? undefined;
            if (projectId && agentId) {
              const project = db.getProject(projectId);
              if (!project) {
                return json({ error: "Project not found." }, { status: 404 });
              }
              const sessions = await runtimeManager.listSessionsForAgent(
                project,
                agentId,
              );
              return json({ sessions });
            }
            const sessions = db.listSessions(projectId).filter((session) =>
              agentId ? session.agentId === agentId : true,
            );
            return json({ sessions });
          }

          if (pathname === "/v1/sessions" && request.method === "POST") {
            const body = createSessionSchema.parse(
              await readLoggedJson("createSession"),
            );
            const project = db.getProject(body.projectId);
            if (!project) {
              return json({ error: "Project not found." }, { status: 404 });
            }
            const snapshot = await runtimeManager.createSession(
              project,
              body.agentId,
              auth.device.id,
            );
            if (!snapshot) {
              return json(
                { error: "Unable to create session." },
                { status: 500 },
              );
            }
            return json({
              session: snapshot.session,
              entries: snapshot.entries,
            });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const snapshot = db.getSessionSnapshot(sessionId);
            if (!snapshot) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({
              session: snapshot.session,
              entries: snapshot.entries,
            });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+$/) &&
            request.method === "PATCH"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const body = updateSessionSchema.parse(
              await readLoggedJson("updateSession"),
            );
            const session = db.updateSession(sessionId, {
              title: body.title,
            });
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({ session });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+$/) &&
            request.method === "DELETE"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            clearPendingPermissionsForSession(sessionId);
            clearPendingQuestionsForSession(sessionId);
            db.deleteSession(sessionId);
            return json({ ok: true });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/prompt$/) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const body = promptSessionSchema.parse(
              await readLoggedJson("promptSession"),
            );
            const prompt: acp.ContentBlock[] =
              body.prompt ?? [{ type: "text", text: body.text! }];
            void startBackgroundPrompt(sessionId, prompt);
            return json({ accepted: true, sessionId });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/state$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json(runtimeManager.getSessionState(sessionId));
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/commands$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const state = runtimeManager.getSessionState(sessionId);
            return json({ commands: state.availableCommands });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/mode$/) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const body = setSessionModeSchema.parse(
              await readLoggedJson("setSessionMode"),
            );
            const state = await runtimeManager.setSessionMode(
              sessionId,
              body.modeId,
            );
            return json(state);
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/config-option$/) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const body = setSessionConfigOptionSchema.parse(
              await readLoggedJson("setSessionConfigOption"),
            );
            const state = await runtimeManager.setSessionConfigOption(sessionId, body);
            return json(state);
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/cancel$/) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            clearPendingPermissionsForSession(sessionId);
            clearPendingQuestionsForSession(sessionId);
            requestLogger.warn("cancel session accepted", {
              sessionId,
            });
            await runtimeManager.cancelSession(sessionId);
            return json({ ok: true });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/permissions$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({
              permissions: [...pendingPermissions.values()]
                .filter((record) => record.sessionId === sessionId)
                .sort((left, right) => left.createdAt - right.createdAt)
                .map(serializePendingPermission),
            });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/questions$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({
              questions: [...pendingQuestions.values()]
                .filter((record) => record.sessionId === sessionId)
                .sort((left, right) => left.createdAt - right.createdAt)
                .map(serializePendingQuestion),
            });
          }

          if (
            pathname.match(
              /^\/v1\/sessions\/[^/]+\/permissions\/[^/]+\/reply$/,
            ) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const requestId = pathname.split("/")[5]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const body = replyPermissionSchema.parse(
              await readLoggedJson("replyPermission"),
            );
            const record = pendingPermissions.get(requestId) ?? null;
            if (!record || record.sessionId !== sessionId) {
              return json(
                { error: "Permission request not found." },
                { status: 404 },
              );
            }
            const outcome = normalizeLegacyPermissionReply(body.reply, record);
            const ok = runtimeManager.replyPermission(
              sessionId,
              requestId,
              outcome.outcome as never,
            );
            if (!ok) {
              return json(
                { error: "Permission reply failed." },
                { status: 400 },
              );
            }
            pendingPermissions.delete(requestId);
            return json({ ok: true });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/questions\/[^/]+\/reply$/) &&
            request.method === "POST"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const requestId = pathname.split("/")[5]!;
            const session = db.getSession(sessionId);
            if (!session) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            const body = replyQuestionSchema.parse(
              await readLoggedJson("replyQuestion"),
            );
            const record = pendingQuestions.get(requestId) ?? null;
            if (!record || record.sessionId !== sessionId) {
              return json(
                { error: "Question request not found." },
                { status: 404 },
              );
            }
            const ok = runtimeManager.replyQuestion(
              sessionId,
              requestId,
              body.outcome === "answered" ? body.answers : null,
            );
            if (!ok) {
              return json(
                { error: "Question reply failed." },
                { status: 400 },
              );
            }
            pendingQuestions.delete(requestId);
            return json({ ok: true });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/todos$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const snapshot = db.getSessionSnapshot(sessionId);
            if (!snapshot) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({
              todos: latestTodosFromEntries(snapshot.entries),
            });
          }

          if (
            pathname.match(/^\/v1\/sessions\/[^/]+\/diff$/) &&
            request.method === "GET"
          ) {
            const sessionId = pathname.split("/")[3]!;
            const snapshot = db.getSessionSnapshot(sessionId);
            if (!snapshot) {
              return json({ error: "Session not found." }, { status: 404 });
            }
            return json({
              diffs: latestDiffsFromEntries(snapshot.entries),
            });
          }

          if (pathname === "/v1/path" && request.method === "GET") {
            const directory = url.searchParams.get("directory");
            return json(getPathInfo(paths, directory));
          }

          if (pathname === "/v1/vcs" && request.method === "GET") {
            const directory = url.searchParams.get("directory");
            return json({
              branch: getGitBranch(directory),
            });
          }

          if (pathname === "/v1/skills" && request.method === "GET") {
            return json([]);
          }

          if (pathname === "/v1/files" && request.method === "GET") {
            const path = url.searchParams.get("path") ?? "";
            const directory = url.searchParams.get("directory");
            return json(await listDirectoryNodes(path, directory));
          }

          if (pathname === "/v1/files/search" && request.method === "GET") {
            const query = url.searchParams.get("query") ?? "";
            const type = url.searchParams.get("type");
            const directory = url.searchParams.get("directory");
            const limit = Number(url.searchParams.get("limit") ?? 200);
            return json(
              await searchFiles({
                query,
                type,
                directory,
                limit,
              }),
            );
          }

          if (pathname === "/v1/resources/search" && request.method === "GET") {
            const query = url.searchParams.get("query") ?? "";
            const directory = url.searchParams.get("directory");
            const limit = Number(url.searchParams.get("limit") ?? 50);
            return json(
              await searchResources({
                directory,
                limit,
                query,
              }),
            );
          }

          if (pathname === "/v1/ptys" && request.method === "GET") {
            return json([]);
          }

          if (pathname === "/v1/ptys" && request.method === "POST") {
            return json(
              { error: "PTY passthrough is not implemented yet." },
              { status: 501 },
            );
          }

          if (
            pathname.match(/^\/v1\/ptys\/[^/]+$/) &&
            ["GET", "DELETE", "PATCH", "PUT"].includes(request.method)
          ) {
            return json(
              { error: "PTY passthrough is not implemented yet." },
              { status: 501 },
            );
          }

          if (
            pathname.match(/^\/v1\/ptys\/[^/]+\/connect$/) &&
            request.method === "GET"
          ) {
            return json(
              { error: "PTY passthrough is not implemented yet." },
              { status: 501 },
            );
          }

          return json({ error: "Not found." }, { status: 404 });
        }

        return json({ error: "Not found." }, { status: 404 });
      } catch (error) {
        return handleRequestError(error);
      }
    },
    websocket: {
      open(socket) {
        wsClients.set(socket, socket.data);
        logger.info("realtime websocket opened", {
          deviceId: socket.data.deviceId,
        });
      },
      close(socket) {
        wsClients.delete(socket);
        logger.info("realtime websocket closed", {
          deviceId: socket.data.deviceId,
        });
      },
      async message(socket, message) {
        try {
          const payload = wsMessageSchema.parse(
            typeof message === "string"
              ? JSON.parse(message)
              : JSON.parse(Buffer.from(message).toString("utf8")),
          );
          logger.info("realtime websocket message", {
            deviceId: socket.data.deviceId,
            type: payload.type,
            payload: sanitizeLogValue(payload),
          });

          switch (payload.type) {
            case "subscribe_session": {
              socket.data.subscriptions.add(payload.sessionId);
              const snapshot = db.getSessionSnapshot(payload.sessionId);
              sendWs(socket, {
                type: "session_snapshot",
                payload: {
                  requestId: payload.requestId ?? null,
                  sessionId: payload.sessionId,
                  snapshot,
                },
              });
              break;
            }
            case "create_session": {
              const project = db.getProject(payload.projectId);
              if (!project) {
                throw new Error("Project not found.");
              }
              const snapshot = await runtimeManager.createSession(
                project,
                payload.agentId,
                socket.data.deviceId,
              );
              sendWs(socket, {
                type: "prompt_result",
                payload: {
                  requestId: payload.requestId ?? null,
                  sessionId: snapshot?.session.id ?? null,
                  snapshot,
                },
              });
              break;
            }
            case "load_session": {
              const snapshot = await runtimeManager.loadSession(
                payload.sessionId,
              );
              sendWs(socket, {
                type: "session_snapshot",
                payload: {
                  requestId: payload.requestId ?? null,
                  sessionId: payload.sessionId,
                  snapshot,
                },
              });
              break;
            }
            case "prompt_session": {
              const prompt: acp.ContentBlock[] =
                payload.prompt ?? [{ type: "text", text: payload.text ?? "" }];
              void startBackgroundPrompt(payload.sessionId, prompt);
              sendWs(socket, {
                type: "prompt_result",
                payload: {
                  requestId: payload.requestId ?? null,
                  sessionId: payload.sessionId,
                  accepted: true,
                },
              });
              break;
            }
            case "cancel_session": {
              await runtimeManager.cancelSession(payload.sessionId);
              sendWs(socket, {
                type: "prompt_result",
                payload: {
                  requestId: payload.requestId ?? null,
                  sessionId: payload.sessionId,
                  cancelled: true,
                },
              });
              break;
            }
            case "reply_permission": {
              const ok = runtimeManager.replyPermission(
                payload.sessionId,
                payload.permissionRequestId,
                payload.outcome as never,
              );
              if (ok) {
                pendingPermissions.delete(payload.permissionRequestId);
              }
              sendWs(socket, {
                type: "permission_reply_result",
                payload: {
                  requestId: payload.requestId ?? null,
                  ok,
                },
              });
              break;
            }
            case "reply_question": {
              const ok = runtimeManager.replyQuestion(
                payload.sessionId,
                payload.questionRequestId,
                payload.outcome.outcome === "answered"
                  ? payload.outcome.answers
                  : null,
              );
              if (ok) {
                pendingQuestions.delete(payload.questionRequestId);
              }
              sendWs(socket, {
                type: "question_reply_result",
                payload: {
                  requestId: payload.requestId ?? null,
                  ok,
                },
              });
              break;
            }
          }
        } catch (error) {
          logger.error("realtime websocket message failed", {
            deviceId: socket.data.deviceId,
            error: serializeError(error),
          });
          let requestId: string | null = null;
          try {
            const raw =
              typeof message === "string"
                ? JSON.parse(message)
                : JSON.parse(Buffer.from(message).toString("utf8"));
            requestId =
              raw && typeof raw === "object" && "requestId" in raw
                ? String((raw as { requestId?: unknown }).requestId ?? "")
                : null;
          } catch {}
          sendWsRequestError(
            socket,
            requestId,
            error instanceof Error ? error.message : "Unknown error",
          );
          sendWs(socket, {
            type: "daemon_warning",
            payload: {
              error: error instanceof Error ? error.message : "Unknown error",
            },
          });
        }
      },
    },
  });

  return {
    server,
    db,
    paths,
    stop() {
      logger.info("daemon stopping");
      server.stop(true);
      db.close();
    },
  };
}
