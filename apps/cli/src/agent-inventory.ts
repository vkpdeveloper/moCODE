import type { Logger } from "winston";

import { syncAgentCatalog } from "./agents";
import { listRegistryAgents } from "./agent-registry";
import { getLogger } from "./logger";
import type { StateDatabase } from "./db";
import type { StatePaths } from "./types";

type AgentChoice = {
  id: string;
  name: string;
};

export type AgentInventorySnapshot = {
  installed: AgentChoice[];
  installable: AgentChoice[];
  uninstallable: AgentChoice[];
  note: string | null;
};

function sortByName<T extends AgentChoice>(items: T[]) {
  return [...items].sort((left, right) => left.name.localeCompare(right.name));
}

export function buildAgentInventory(options: {
  descriptors: Array<{
    id: string;
    name: string;
    source: string;
    installState: "detected" | "configured" | "unavailable";
    binaryPath: string | null;
    metadata: Record<string, unknown>;
  }>;
  registryAgents: Array<{
    id: string;
    name: string;
  }>;
  registryAvailable?: boolean;
}) {
  const registryAvailable = options.registryAvailable ?? true;
  const registryNameById = new Map(options.registryAgents.map((agent) => [agent.id, agent.name]));
  const acpDescriptors = options.descriptors.filter((descriptor) => descriptor.source === "acp");

  const installed = sortByName(
    acpDescriptors
      .filter((descriptor) => descriptor.installState === "configured")
      .map((descriptor) => ({
        id: descriptor.id,
        name: registryNameById.get(descriptor.id) ?? descriptor.name,
      })),
  );

  const uninstallable = installed;

  const installedOrDetectedIds = new Set(
    acpDescriptors.filter((descriptor) => descriptor.binaryPath).map((descriptor) => descriptor.id),
  );

  const installable = registryAvailable
    ? sortByName(
        options.registryAgents
          .filter((agent) => !installedOrDetectedIds.has(agent.id))
          .map((agent) => ({
            id: agent.id,
            name: agent.name,
          })),
      )
    : [];

  return {
    installed,
    installable,
    uninstallable,
  };
}

export async function listAgentInventory(
  db: StateDatabase,
  paths: StatePaths,
  logger: Logger = getLogger("agent-inventory"),
): Promise<AgentInventorySnapshot> {
  const descriptors = syncAgentCatalog(db, paths);

  try {
    const registryAgents = await listRegistryAgents(paths, logger);
    return {
      ...buildAgentInventory({
        descriptors,
        registryAgents,
      }),
      note: null,
    };
  } catch (error) {
    logger.warn("failed to load registry agents for inventory", {
      error: error instanceof Error ? error.message : String(error),
    });

    return {
      ...buildAgentInventory({
        descriptors,
        registryAgents: [],
        registryAvailable: false,
      }),
      note: "Registry unavailable.",
    };
  }
}
