export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

export type JsonObject = { [key: string]: JsonValue };

export type ProjectRecord = {
  id: string;
  rootPath: string;
  detectedName: string;
  displayName: string | null;
  preferredAgentId: string | null;
  createdAt: string;
  updatedAt: string;
  lastOpenedAt: string | null;
};

export type SessionRecord = {
  id: string;
  projectId: string;
  agentId: string;
  agentSessionId: string;
  cwd: string;
  title: string | null;
  status: string;
  controllerDeviceId: string | null;
  createdAt: string;
  updatedAt: string;
  lastStopReason: string | null;
  capabilitiesJson: string | null;
};

export type SessionEntryRecord = {
  id: string;
  sessionId: string;
  seq: number;
  kind: string;
  payloadJson: string;
  createdAt: string;
};

export type AgentRecord = {
  id: string;
  kind: string;
  source: string;
  installState: string;
  version: string | null;
  binaryPath: string | null;
  metadataJson: string | null;
  updatedAt: string;
};

export type PairedDeviceRecord = {
  id: string;
  name: string;
  tokenHash: string;
  createdAt: string;
  lastSeenAt: string | null;
  revokedAt: string | null;
};

export type AgentSpec = {
  id: string;
  name: string;
  kind: string;
  source: string;
  commandCandidates: string[];
  args: string[];
  env?: Record<string, string>;
  envVar?: string;
  registryId?: string;
};

export type AgentDescriptor = {
  id: string;
  name: string;
  kind: string;
  source: string;
  installState: "detected" | "configured" | "unavailable";
  binaryPath: string | null;
  version: string | null;
  metadata: JsonObject;
};

export type AgentInventoryStatus =
  | "installed"
  | "detected"
  | "available"
  | "unavailable";

export type AgentInventoryItem = {
  id: string;
  registryId: string | null;
  name: string;
  description: string | null;
  status: AgentInventoryStatus;
  binaryPath: string | null;
  managed: boolean;
  installable: boolean;
  uninstallable: boolean;
};

export type SessionSnapshot = {
  session: SessionRecord;
  entries: SessionEntrySnapshot[];
};

export type SessionEntrySnapshot = {
  id: string;
  seq: number;
  kind: string;
  payload: JsonValue;
  createdAt: string;
};

export type StatePaths = {
  stateDir: string;
  cacheDir: string;
  configDir: string;
  logDir: string;
  managedHomeDir: string;
  managedBinDir: string;
  managedAgentsDir: string;
  managedAgentsManifestPath: string;
  databasePath: string;
};

export type BroadcastEvent = {
  type: string;
  payload: JsonObject;
};
