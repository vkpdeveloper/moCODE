import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { spawn } from "node:child_process";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";

import type { Logger } from "winston";

import { getLogger } from "./logger";
import { syncAgentCatalog, upsertManagedAgentSpec } from "./agents";
import type { StateDatabase } from "./db";
import type { AgentDescriptor, AgentSpec, StatePaths } from "./types";

const ACP_REGISTRY_URL =
  "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json";
const GITHUB_REGISTRY_RAW_BASE =
  "https://raw.githubusercontent.com/agentclientprotocol/registry/main";
const REGISTRY_CACHE_TTL_MS = 1000 * 60 * 60 * 12;

const AGENT_ID_ALIASES: Record<string, string> = {
  codex: "codex-acp",
  claude: "claude-acp",
  "claude-agent": "claude-acp",
  "claude-agent-acp": "claude-acp",
  "cursor-agent": "cursor",
};

type RegistryBinaryTarget = {
  archive: string;
  cmd: string;
  args?: string[];
  env?: Record<string, string>;
};

type RegistryNpxTarget = {
  package: string;
  args?: string[];
};

type RegistryDistribution = {
  binary?: Record<string, RegistryBinaryTarget>;
  npx?: RegistryNpxTarget;
};

export type RegistryAgent = {
  id: string;
  name: string;
  version: string;
  description?: string;
  repository?: string;
  authors?: string[];
  license?: string;
  icon?: string;
  distribution?: RegistryDistribution;
};

type RegistryIndex = {
  version: string;
  agents: RegistryAgent[];
};

type CachedRegistryIndex = {
  fetchedAt: string;
  data: RegistryIndex;
};

type InstallPlan =
  | {
      kind: "npx";
      target: RegistryNpxTarget;
      wrapperName: string;
      execName: string;
      commandCandidates: string[];
      args: string[];
      env: Record<string, string>;
      summary: string;
    }
  | {
      kind: "binary";
      target: RegistryBinaryTarget;
      wrapperName: string;
      commandCandidates: string[];
      args: string[];
      env: Record<string, string>;
      summary: string;
    };

export type AgentActivationResult = {
  agentId: string;
  registryId: string | null;
  status:
    | "installed"
    | "already_available"
    | "already_configured"
    | "dry_run"
    | "failed";
  binaryPath: string | null;
  message: string;
};

export type AgentActivationProgressEvent = {
  progress: number;
  stage: string;
  message: string;
};

type ActivateAgentOptions = {
  force?: boolean;
  dryRun?: boolean;
  logger?: Logger;
  onProgress?: (event: AgentActivationProgressEvent) => void;
};

function emitProgress(
  onProgress: ActivateAgentOptions["onProgress"],
  progress: number,
  stage: string,
  message: string,
) {
  onProgress?.({
    progress,
    stage,
    message,
  });
}

function normalizeAgentId(agentId: string) {
  return AGENT_ID_ALIASES[agentId] ?? agentId;
}

function getMacPlatformKey() {
  if (process.platform !== "darwin") {
    throw new Error("ACP activation currently supports macOS only.");
  }

  if (process.arch === "arm64") {
    return "darwin-aarch64";
  }

  if (process.arch === "x64") {
    return "darwin-x86_64";
  }

  throw new Error(`Unsupported macOS architecture: ${process.arch}`);
}

function getRegistryCacheDir(paths: StatePaths) {
  return join(paths.cacheDir, "registry");
}

function getRegistryIndexCachePath(paths: StatePaths) {
  return join(getRegistryCacheDir(paths), "registry.json");
}

function getRegistryAgentsCacheDir(paths: StatePaths) {
  return join(getRegistryCacheDir(paths), "agents");
}

function getRegistryAgentCachePath(paths: StatePaths, agentId: string) {
  return join(getRegistryAgentsCacheDir(paths), `${agentId}.json`);
}

function getRegistryIconsCacheDir(paths: StatePaths) {
  return join(getRegistryCacheDir(paths), "icons");
}

function getRegistryIconCachePath(paths: StatePaths, registryId: string) {
  return join(getRegistryIconsCacheDir(paths), `${registryId}.svg`);
}

function getRegistryRepoFileUrl(agentId: string, filename: string) {
  return `${GITHUB_REGISTRY_RAW_BASE}/${agentId}/${filename}`;
}

function getRegistryRepoIconUrl(agentId: string) {
  return getRegistryRepoFileUrl(agentId, "icon.svg");
}

async function runCommand(
  command: string,
  args: string[],
  options: {
    cwd?: string;
    env?: Record<string, string>;
  } = {},
) {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: {
        ...process.env,
        ...options.env,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stderr = "";

    child.stderr.on("data", (chunk) => {
      stderr += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(
        new Error(
          stderr.trim() || `${command} ${args.join(" ")} exited with code ${code ?? -1}.`,
        ),
      );
    });
  });
}

async function runCommandWithOutput(command: string, args: string[]) {
  return await new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(command, args, {
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
    });

    child.stderr.on("data", (chunk) => {
      stderr += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }

      reject(
        new Error(
          stderr.trim() || `${command} ${args.join(" ")} exited with code ${code ?? -1}.`,
        ),
      );
    });
  });
}

async function readJsonFile<T>(path: string) {
  try {
    const raw = await readFile(path, "utf8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

async function fetchJson<T>(url: string) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }
  return (await response.json()) as T;
}

async function loadRegistryIndex(paths: StatePaths, logger: Logger) {
  const cached = await readJsonFile<CachedRegistryIndex>(getRegistryIndexCachePath(paths));
  const fetchedAt = cached ? Date.parse(cached.fetchedAt) : Number.NaN;
  const isFresh =
    cached &&
    Number.isFinite(fetchedAt) &&
    Date.now() - fetchedAt < REGISTRY_CACHE_TTL_MS;

  if (isFresh) {
    return cached.data;
  }

  try {
    logger.info("fetching acp registry", { url: ACP_REGISTRY_URL });
    const live = await fetchJson<RegistryIndex>(ACP_REGISTRY_URL);
    await mkdir(getRegistryCacheDir(paths), { recursive: true });
    await writeFile(
      getRegistryIndexCachePath(paths),
      `${JSON.stringify({ fetchedAt: new Date().toISOString(), data: live }, null, 2)}\n`,
      "utf8",
    );
    return live;
  } catch (error) {
    if (cached) {
      logger.warn("using stale registry index cache", {
        error: error instanceof Error ? error.message : String(error),
      });
      return cached.data;
    }
    throw error;
  }
}

async function loadRegistryAgent(paths: StatePaths, agentId: string, logger: Logger) {
  const normalizedId = normalizeAgentId(agentId);
  const cachePath = getRegistryAgentCachePath(paths, normalizedId);
  const cached = await readJsonFile<RegistryAgent>(cachePath);

  try {
    const live = await fetchJson<RegistryAgent>(
      getRegistryRepoFileUrl(normalizedId, "agent.json"),
    );
    await mkdir(getRegistryAgentsCacheDir(paths), { recursive: true });
    await writeFile(cachePath, `${JSON.stringify(live, null, 2)}\n`, "utf8");
    return live;
  } catch (error) {
    if (cached) {
      logger.warn("using cached registry agent definition", {
        agentId: normalizedId,
        error: error instanceof Error ? error.message : String(error),
      });
      return cached;
    }
  }

  const index = await loadRegistryIndex(paths, logger);
  const fromIndex = index.agents.find((entry) => entry.id === normalizedId) ?? null;
  if (!fromIndex) {
    throw new Error(`Registry agent ${normalizedId} was not found.`);
  }
  return fromIndex;
}

function inferAgentKind(agent: RegistryAgent) {
  return agent.id.includes("acp") ? "adapter" : "native";
}

function getManagedBinaryPath(paths: StatePaths, commandName: string) {
  return join(
    paths.managedBinDir,
    process.platform === "win32" ? `${commandName}.cmd` : commandName,
  );
}

function normalizeCommandPath(value: string) {
  return value
    .replace(/^[.][/\\]/, "")
    .split(/[\\/]+/)
    .filter(Boolean);
}

function buildUnixNpxWrapper(pkg: string, execName: string) {
  return `#!/usr/bin/env sh
set -eu
exec npx --yes --package "${pkg}" ${execName} "$@"
`;
}

function buildUnixBinaryWrapper(payloadPath: string) {
  return `#!/usr/bin/env sh
set -eu
exec "${payloadPath}" "$@"
`;
}

async function writeManagedWrapper(
  paths: StatePaths,
  commandName: string,
  content: string,
) {
  const wrapperPath = getManagedBinaryPath(paths, commandName);
  await mkdir(paths.managedBinDir, { recursive: true });
  await writeFile(wrapperPath, content, "utf8");
  if (process.platform !== "win32") {
    await chmod(wrapperPath, 0o755);
  }
  return wrapperPath;
}

async function extractArchive(archivePath: string, destinationPath: string) {
  if (archivePath.endsWith(".zip")) {
    await runCommand("unzip", ["-oq", archivePath, "-d", destinationPath]);
    return;
  }

  if (archivePath.endsWith(".tar.gz") || archivePath.endsWith(".tgz")) {
    await runCommand("tar", ["-xzf", archivePath, "-C", destinationPath]);
    return;
  }

  throw new Error(`Unsupported archive format: ${archivePath}`);
}

async function resolveNpxExecutableName(
  packageName: string,
  fallbackName: string,
  logger: Logger,
) {
  try {
    const result = await runCommandWithOutput("npm", ["view", packageName, "bin", "--json"]);
    const parsed = JSON.parse(result.stdout) as string | Record<string, string>;

    if (typeof parsed === "string" && parsed.trim().length > 0) {
      return parsed.trim();
    }

    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      if (typeof parsed[fallbackName] === "string") {
        return fallbackName;
      }

      const keys = Object.keys(parsed);
      if (keys.length === 1) {
        return keys[0]!;
      }
    }
  } catch (error) {
    logger.warn("failed to resolve npm package bin", {
      packageName,
      fallbackName,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  return fallbackName;
}

async function buildInstallPlan(agent: RegistryAgent, logger: Logger): Promise<InstallPlan> {
  const npx = agent.distribution?.npx ?? null;
  if (npx?.package) {
    const execName = await resolveNpxExecutableName(npx.package, agent.id, logger);
    return {
      kind: "npx",
      target: npx,
      wrapperName: agent.id,
      execName,
      commandCandidates: [...new Set([agent.id, execName])],
      args: npx.args ?? [],
      env: {},
      summary: `npx --yes --package ${npx.package} ${execName}`,
    };
  }

  const binary = agent.distribution?.binary?.[getMacPlatformKey()] ?? null;
  if (binary) {
    const payloadCommand = basename(binary.cmd).replace(/\.exe$/i, "");
    return {
      kind: "binary",
      target: binary,
      wrapperName: agent.id,
      commandCandidates: [...new Set([agent.id, payloadCommand])],
      args: binary.args ?? [],
      env: binary.env ?? {},
      summary: binary.archive,
    };
  }

  throw new Error(`Registry agent ${agent.id} does not have a macOS install target.`);
}

async function installFromNpx(
  paths: StatePaths,
  plan: Extract<InstallPlan, { kind: "npx" }>,
  onProgress?: (event: AgentActivationProgressEvent) => void,
) {
  emitProgress(onProgress, 75, "Wrapper", "Writing managed wrapper");
  return await writeManagedWrapper(
    paths,
    plan.wrapperName,
    buildUnixNpxWrapper(plan.target.package, plan.execName),
  );
}

async function installFromBinary(
  paths: StatePaths,
  agent: RegistryAgent,
  plan: Extract<InstallPlan, { kind: "binary" }>,
  logger: Logger,
  onProgress?: (event: AgentActivationProgressEvent) => void,
) {
  const installDir = join(paths.managedAgentsDir, agent.id);
  const tempDir = await mkdtemp(join(tmpdir(), "mocode-agent-"));
  const archivePath = join(
    tempDir,
    plan.target.archive.endsWith(".zip") ? "agent.zip" : "agent.tar.gz",
  );

  try {
    emitProgress(onProgress, 45, "Download", "Downloading agent archive");
    logger.info("downloading agent archive", {
      registryId: agent.id,
      archive: plan.target.archive,
    });
    const response = await fetch(plan.target.archive);
    if (!response.ok) {
      throw new Error(
        `Failed to download ${agent.id}: ${response.status} ${response.statusText}`,
      );
    }

    const archiveBuffer = Buffer.from(await response.arrayBuffer());
    await writeFile(archivePath, archiveBuffer);
    logger.info("downloaded agent archive", {
      registryId: agent.id,
      bytes: archiveBuffer.byteLength,
      archivePath,
    });
    emitProgress(onProgress, 68, "Extract", "Extracting archive");
    await rm(installDir, { recursive: true, force: true });
    await mkdir(installDir, { recursive: true });
    await extractArchive(archivePath, installDir);
    logger.info("extracted agent archive", {
      registryId: agent.id,
      installDir,
    });

    const payloadPath = join(installDir, ...normalizeCommandPath(plan.target.cmd));
    await chmod(payloadPath, 0o755);
    emitProgress(onProgress, 82, "Prepare", "Preparing executable");
    logger.info("prepared agent binary", {
      registryId: agent.id,
      payloadPath,
    });

    emitProgress(onProgress, 90, "Wrapper", "Writing managed wrapper");
    return await writeManagedWrapper(
      paths,
      plan.wrapperName,
      buildUnixBinaryWrapper(payloadPath),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function buildManagedSpec(agent: RegistryAgent, plan: InstallPlan): AgentSpec {
  return {
    id: agent.id,
    name: agent.name,
    kind: inferAgentKind(agent),
    source: "acp",
    registryId: agent.id,
    commandCandidates: plan.commandCandidates,
    args: plan.args,
    env: plan.env,
  };
}

export async function listRegistryAgents(
  paths: StatePaths,
  logger: Logger = getLogger("agent-registry"),
) {
  const index = await loadRegistryIndex(paths, logger);
  return [...index.agents].sort((a, b) => a.name.localeCompare(b.name));
}

export async function activateRegistryAgent(
  db: StateDatabase,
  paths: StatePaths,
  agentId: string,
  options: ActivateAgentOptions = {},
) {
  const logger = options.logger ?? getLogger("agent-registry");
  const onProgress = options.onProgress;
  const normalizedId = normalizeAgentId(agentId);
  const current = new Map(syncAgentCatalog(db, paths).map((entry) => [entry.id, entry]));
  const existing = current.get(normalizedId) ?? null;

  emitProgress(onProgress, 10, "Check", "Checking current installation");

  if (options.dryRun && !options.force && existing?.binaryPath) {
    return {
      agentId: normalizedId,
      registryId: normalizedId,
      status: "dry_run",
      binaryPath: existing.binaryPath,
      message:
        existing.installState === "configured"
          ? "Managed agent is already installed. Use --force to reinstall."
          : "Agent is already available on PATH. Use --force to replace it with a managed wrapper.",
    } satisfies AgentActivationResult;
  }

  if (!options.force && existing?.binaryPath) {
    return {
      agentId: normalizedId,
      registryId: normalizedId,
      status:
        existing.installState === "configured"
          ? "already_configured"
          : "already_available",
      binaryPath: existing.binaryPath,
      message:
        existing.installState === "configured"
          ? "Managed agent is already installed."
          : "Agent is already available on PATH.",
    } satisfies AgentActivationResult;
  }

  emitProgress(onProgress, 22, "Metadata", "Loading agent metadata");
  const agent = await loadRegistryAgent(paths, normalizedId, logger);
  emitProgress(onProgress, 34, "Plan", "Preparing installation plan");
  const plan = await buildInstallPlan(agent, logger);

  if (options.dryRun) {
    return {
      agentId: agent.id,
      registryId: agent.id,
      status: "dry_run",
      binaryPath: getManagedBinaryPath(paths, plan.wrapperName),
      message: `Would install via ${plan.kind}: ${plan.summary}`,
    } satisfies AgentActivationResult;
  }

  try {
    emitProgress(
      onProgress,
      plan.kind === "npx" ? 55 : 40,
      plan.kind === "npx" ? "Wrapper" : "Install",
      plan.kind === "npx" ? "Preparing managed wrapper" : "Starting installation",
    );
    const binaryPath =
      plan.kind === "npx"
        ? await installFromNpx(paths, plan, onProgress)
        : await installFromBinary(paths, agent, plan, logger, onProgress);

    emitProgress(onProgress, 100, "Finalize", "Finalizing installation");
    upsertManagedAgentSpec(paths, buildManagedSpec(agent, plan));
    const refreshed = new Map(syncAgentCatalog(db, paths).map((entry) => [entry.id, entry]));
    const resolved = refreshed.get(agent.id);

    return {
      agentId: agent.id,
      registryId: agent.id,
      status: "installed",
      binaryPath: resolved?.binaryPath ?? binaryPath,
      message: `Installed ${agent.name} ${agent.version} via ${plan.kind}.`,
    } satisfies AgentActivationResult;
  } catch (error) {
    logger.error("agent activation failed", {
      agentId: normalizedId,
      error,
    });
    return {
      agentId: normalizedId,
      registryId: normalizedId,
      status: "failed",
      binaryPath: existing?.binaryPath ?? null,
      message: error instanceof Error ? error.message : String(error),
    } satisfies AgentActivationResult;
  }
}

async function readCachedIconSvg(paths: StatePaths, registryId: string) {
  const iconPath = getRegistryIconCachePath(paths, registryId);

  try {
    const info = await stat(iconPath);
    if (!info.isFile()) {
      return null;
    }
    return await readFile(iconPath, "utf8");
  } catch {
    return null;
  }
}

async function loadRegistryIconSvg(
  paths: StatePaths,
  agent: RegistryAgent,
  logger: Logger,
) {
  const cached = await readCachedIconSvg(paths, agent.id);
  if (cached) {
    return cached;
  }

  const iconSources = [
    getRegistryRepoIconUrl(agent.id),
    agent.icon ?? null,
  ].filter((value): value is string => Boolean(value));

  for (const source of iconSources) {
    try {
      const response = await fetch(source);
      if (!response.ok) {
        continue;
      }

      const svg = await response.text();
      await mkdir(getRegistryIconsCacheDir(paths), { recursive: true });
      await writeFile(getRegistryIconCachePath(paths, agent.id), svg, "utf8");
      return svg;
    } catch (error) {
      logger.warn("failed to fetch registry icon", {
        registryId: agent.id,
        source,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return null;
}

export async function enrichAgentDescriptorsFromRegistry(
  descriptors: AgentDescriptor[],
  paths: StatePaths,
  logger: Logger = getLogger("agent-registry"),
) {
  let registryAgents: RegistryAgent[];

  try {
    registryAgents = await listRegistryAgents(paths, logger);
  } catch (error) {
    logger.warn("failed to enrich agents from registry", {
      error: error instanceof Error ? error.message : String(error),
    });
    return descriptors;
  }

  const registryById = new Map(registryAgents.map((entry) => [entry.id, entry]));

  return await Promise.all(
    descriptors.map(async (descriptor) => {
      const registryId =
        typeof descriptor.metadata.registryId === "string"
          ? descriptor.metadata.registryId
          : null;
      if (!registryId) {
        return descriptor;
      }

      const agent = registryById.get(registryId);
      if (!agent) {
        return descriptor;
      }

      const iconSvg = await loadRegistryIconSvg(paths, agent, logger);

      return {
        ...descriptor,
        name: agent.name || descriptor.name,
        version: agent.version ?? descriptor.version,
        metadata: {
          ...descriptor.metadata,
          registryId: agent.id,
          registryName: agent.name ?? null,
          registryDescription: agent.description ?? null,
          repository: agent.repository ?? null,
          authors: agent.authors ?? [],
          license: agent.license ?? null,
          iconUrl: agent.icon ?? getRegistryRepoIconUrl(agent.id),
          iconSvg,
        },
      } satisfies AgentDescriptor;
    }),
  );
}
