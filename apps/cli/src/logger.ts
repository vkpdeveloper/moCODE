import { join } from "node:path";

import winston from "winston";

import { getStatePaths } from "./paths";

const REDACTED_KEY = /authorization|token|secret|password|cookie|api[-_]?key/i;
const MAX_DEPTH = 5;
const MAX_ARRAY_ITEMS = 20;
const MAX_STRING_LENGTH = 500;

let rootLogger: winston.Logger | null = null;

function isVerboseFlag(value: string) {
  return value === "--verbose" || value === "-v";
}

export function isVerboseLoggingEnabled() {
  return process.argv.some(isVerboseFlag);
}

function maskSecret(value: string) {
  if (value.length <= 8) {
    return "***";
  }
  return `${value.slice(0, 3)}***${value.slice(-3)}`;
}

function truncateText(value: string, max = MAX_STRING_LENGTH) {
  if (value.length <= max) {
    return value;
  }
  return `${value.slice(0, max)}… (${value.length} chars)`;
}

export function summarizeText(value: string | null | undefined, max = 180) {
  if (!value) {
    return value ?? null;
  }
  return truncateText(value.replace(/\s+/g, " ").trim(), max);
}

export function sanitizeLogValue(
  value: unknown,
  depth = 0,
  parentKey = "",
): unknown {
  if (depth > MAX_DEPTH) {
    return "[max-depth]";
  }

  if (value === null || value === undefined) {
    return value ?? null;
  }

  if (typeof value === "string") {
    return REDACTED_KEY.test(parentKey)
      ? maskSecret(value)
      : truncateText(value);
  }

  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
  ) {
    return value;
  }

  if (value instanceof Uint8Array) {
    return `[${value.byteLength} bytes]`;
  }

  if (Array.isArray(value)) {
    const items = value
      .slice(0, MAX_ARRAY_ITEMS)
      .map((item) => sanitizeLogValue(item, depth + 1, parentKey));
    if (value.length > MAX_ARRAY_ITEMS) {
      items.push(`… ${value.length - MAX_ARRAY_ITEMS} more items`);
    }
    return items;
  }

  if (value instanceof Error) {
    return serializeError(value);
  }

  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const output: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(record)) {
      if (REDACTED_KEY.test(key)) {
        output[key] =
          typeof entry === "string" ? maskSecret(entry) : "[redacted]";
        continue;
      }
      output[key] = sanitizeLogValue(entry, depth + 1, key);
    }
    return output;
  }

  return String(value);
}

export function serializeError(error: unknown) {
  if (error instanceof Error) {
    return sanitizeLogValue({
      name: error.name,
      message: error.message,
      stack: error.stack,
    });
  }
  return sanitizeLogValue(error);
}

function createRootLogger() {
  const paths = getStatePaths();
  const verbose = isVerboseLoggingEnabled();
  const level = process.env.MOCODE_LOG_LEVEL ?? "info";
  const consoleLevel = process.env.MOCODE_CONSOLE_LOG_LEVEL ?? "info";
  const jsonFormat = winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json(),
  );
  const consoleFormat = winston.format.combine(
    winston.format.colorize(),
    winston.format.timestamp(),
    winston.format.printf(({ level, message, timestamp, scope, ...meta }) => {
      const details =
        Object.keys(meta).length > 0
          ? ` ${JSON.stringify(sanitizeLogValue(meta))}`
          : "";
      return `${timestamp} ${level}${scope ? ` [${String(scope)}]` : ""}: ${String(message)}${details}`;
    }),
  );

  return winston.createLogger({
    level,
    defaultMeta: {
      service: "mocode-cli",
    },
    transports: [
      new winston.transports.Console({
        silent: !verbose,
        level: consoleLevel,
        format: consoleFormat,
      }),
      new winston.transports.File({
        filename: join(paths.logDir, "cli.log"),
        silent: !verbose,
        level,
        format: jsonFormat,
      }),
      new winston.transports.File({
        filename: join(paths.logDir, "error.log"),
        silent: !verbose,
        level: "error",
        format: jsonFormat,
      }),
    ],
    exitOnError: false,
  });
}

export function getLogger(scope?: string) {
  rootLogger ??= createRootLogger();
  return scope ? rootLogger.child({ scope }) : rootLogger;
}
