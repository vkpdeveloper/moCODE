import { existsSync } from "node:fs";
import { rm } from "node:fs/promises";
import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve, sep } from "node:path";

import type { AgentDescriptor, AgentSpec, StatePaths } from "./types";
import { StateDatabase } from "./db";

export const AGENT_SPECS: AgentSpec[] = [
  {
    id: "opencode",
    name: "OpenCode",
    kind: "native",
    source: "acp",
    registryId: "opencode",
    commandCandidates: ["opencode"],
    args: ["acp"],
    envVar: "MOCODE_OPENCODE_BIN",
  },
  {
    id: "gemini",
    name: "Gemini CLI",
    kind: "native",
    source: "acp",
    registryId: "gemini",
    commandCandidates: ["gemini"],
    args: ["--experimental-acp"],
    envVar: "MOCODE_GEMINI_BIN",
  },
];

type ManagedAgentManifest = {
  version: 1;
  agents: AgentSpec[];
};

function isAgentSpec(value: unknown): value is AgentSpec {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.id === "string" &&
    typeof candidate.name === "string" &&
    typeof candidate.kind === "string" &&
    typeof candidate.source === "string" &&
    Array.isArray(candidate.commandCandidates) &&
    candidate.commandCandidates.every((entry) => typeof entry === "string") &&
    Array.isArray(candidate.args) &&
    candidate.args.every((entry) => typeof entry === "string") &&
    (candidate.env === undefined ||
      (typeof candidate.env === "object" &&
        candidate.env !== null &&
        !Array.isArray(candidate.env) &&
        Object.values(candidate.env).every((entry) => typeof entry === "string")))
  );
}

function readManagedAgentManifest(paths: StatePaths): ManagedAgentManifest {
  try {
    const raw = readFileSync(paths.managedAgentsManifestPath, "utf8");
    const parsed = JSON.parse(raw) as {
      version?: unknown;
      agents?: unknown;
    };

    if (parsed.version !== 1 || !Array.isArray(parsed.agents)) {
      return { version: 1, agents: [] };
    }

    return {
      version: 1,
      agents: parsed.agents.filter(isAgentSpec),
    };
  } catch {
    return { version: 1, agents: [] };
  }
}

function writeManagedAgentManifest(paths: StatePaths, manifest: ManagedAgentManifest) {
  writeFileSync(paths.managedAgentsManifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

export function listManagedAgentSpecs(paths: StatePaths) {
  return readManagedAgentManifest(paths).agents;
}

export function upsertManagedAgentSpec(paths: StatePaths, spec: AgentSpec) {
  const manifest = readManagedAgentManifest(paths);
  const nextAgents = manifest.agents.filter((entry) => entry.id !== spec.id);
  nextAgents.push(spec);
  nextAgents.sort((a, b) => a.name.localeCompare(b.name));
  writeManagedAgentManifest(paths, {
    version: 1,
    agents: nextAgents,
  });
}

export function removeManagedAgentSpec(paths: StatePaths, agentId: string) {
  const manifest = readManagedAgentManifest(paths);
  const nextAgents = manifest.agents.filter((entry) => entry.id !== agentId);

  if (nextAgents.length === manifest.agents.length) {
    return false;
  }

  writeManagedAgentManifest(paths, {
    version: 1,
    agents: nextAgents,
  });

  return true;
}

export function getAllAgentSpecs(paths: StatePaths) {
  const byId = new Map<string, AgentSpec>();

  for (const spec of AGENT_SPECS) {
    byId.set(spec.id, spec);
  }

  for (const spec of listManagedAgentSpecs(paths)) {
    byId.set(spec.id, spec);
  }

  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function getManagedBinaryName(spec: AgentSpec) {
  return `${spec.commandCandidates[0]}${process.platform === "win32" ? ".cmd" : ""}`;
}

export function resolveConfiguredPath(spec: AgentSpec, paths: StatePaths) {
  const envPath = spec.envVar ? process.env[spec.envVar] : null;
  if (envPath) {
    return envPath;
  }

  return join(paths.managedBinDir, getManagedBinaryName(spec));
}

function resolveBinaryPath(spec: AgentSpec, paths: StatePaths) {
  const configured = resolveConfiguredPath(spec, paths);
  if (configured && existsSync(configured)) {
    return {
      binaryPath: configured,
      installState: "configured",
    } as const;
  }

  for (const candidate of spec.commandCandidates) {
    const found = Bun.which(candidate);
    if (found) {
      return {
        binaryPath: found,
        installState: "detected",
      } as const;
    }
  }

  return {
    binaryPath: null,
    installState: "unavailable",
  } as const;
}

export function syncAgentCatalog(db: StateDatabase, paths: StatePaths): AgentDescriptor[] {
  const descriptors = getAllAgentSpecs(paths).map((spec) => {
    const resolved = resolveBinaryPath(spec, paths);
    const descriptor: AgentDescriptor = {
      id: spec.id,
      name: spec.name,
      kind: spec.kind,
      source: spec.source,
      installState: resolved.installState,
      binaryPath: resolved.binaryPath,
      version: null,
      metadata: {
        args: spec.args,
        env: spec.env ?? {},
        commandCandidates: spec.commandCandidates,
        registryId: spec.registryId ?? null,
        envVar: spec.envVar ?? null,
      },
    };

    db.upsertAgent(descriptor);
    return descriptor;
  });

  return descriptors;
}

export function getAgentSpec(agentId: string, paths?: StatePaths) {
  if (paths) {
    return getAllAgentSpecs(paths).find((spec) => spec.id === agentId) ?? null;
  }

  return AGENT_SPECS.find((spec) => spec.id === agentId) ?? null;
}

function isManagedPath(targetPath: string, managedRoot: string) {
  const normalizedTarget = resolve(targetPath);
  const normalizedRoot = resolve(managedRoot);
  return (
    normalizedTarget === normalizedRoot ||
    normalizedTarget.startsWith(`${normalizedRoot}${sep}`)
  );
}

export type ManagedAgentUninstallResult = {
  agentId: string;
  status: "uninstalled" | "not_managed";
  message: string;
};

export async function uninstallManagedAgent(
  db: StateDatabase,
  paths: StatePaths,
  agentId: string,
): Promise<ManagedAgentUninstallResult> {
  const spec = listManagedAgentSpecs(paths).find((entry) => entry.id === agentId) ?? null;
  if (!spec) {
    return {
      agentId,
      status: "not_managed",
      message: "Agent is not managed by moCODE.",
    };
  }

  const configuredPath = resolveConfiguredPath(spec, paths);
  if (configuredPath && isManagedPath(configuredPath, paths.managedBinDir)) {
    await rm(configuredPath, { force: true });
  }

  await rm(join(paths.managedAgentsDir, spec.id), { recursive: true, force: true });
  removeManagedAgentSpec(paths, spec.id);
  db.deleteAgent(spec.id);
  syncAgentCatalog(db, paths);

  return {
    agentId: spec.id,
    status: "uninstalled",
    message: `Removed managed agent ${spec.name}.`,
  };
}
