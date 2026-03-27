import { randomUUID } from "node:crypto";

import * as acp from "@agentclientprotocol/sdk";
import type { Logger } from "winston";

import type { StateDatabase } from "./db";
import type {
  BroadcastEvent,
  JsonObject,
  JsonValue,
  ProjectRecord,
  SessionRecord,
  SessionSnapshot,
  StatePaths,
} from "./types";

export type RuntimeSessionBinding = {
  localSessionId: string;
  agentSessionId: string;
  loaded: boolean;
};

export type SessionConfigRequest =
  | {
      configId: string;
      type: "boolean";
      value: boolean;
    }
  | {
      type: "value";
      configId: string;
      value: string;
    };

export type RuntimeListSessionsResponse = {
  sessions: acp.SessionInfo[];
  nextCursor?: string | null;
};

export type StoredSessionCapabilities = {
  agentCapabilities?: acp.AgentCapabilities | null;
  authMethods?: acp.AuthMethod[] | null;
  availableCommands?: acp.AvailableCommand[] | null;
  configOptions?: acp.SessionConfigOption[] | null;
  models?: acp.SessionModelState | null;
  modes?: acp.SessionModeState | null;
};

export type AgentLaunchMetadata = {
  args: string[];
  env: Record<string, string>;
};

type PendingPermissionHandler = {
  localSessionId: string;
  handler: (outcome: acp.RequestPermissionOutcome) => Promise<void> | void;
};

type PendingQuestionHandler = {
  localSessionId: string;
  handler: (answers: Record<string, string[]> | null) => Promise<void> | void;
};

export interface ManagedRuntime {
  ensureStarted(): Promise<void>;
  listAuthMethods(): acp.AuthMethod[];
  getCapabilities(): acp.AgentCapabilities | null;
  supportsSessionListing(): boolean;
  authenticate(params: acp.AuthenticateRequest): Promise<acp.AuthenticateResponse>;
  createSession(
    project: ProjectRecord,
    controllerDeviceId: string | null,
  ): Promise<SessionRecord>;
  ensureSessionLoaded(
    session: SessionRecord,
  ): Promise<RuntimeSessionBinding | null>;
  promptSession(
    session: SessionRecord,
    prompt: acp.ContentBlock[],
  ): Promise<Record<string, unknown>>;
  cancelSession(session: SessionRecord): Promise<void>;
  listSessions(cwd: string): Promise<RuntimeListSessionsResponse>;
  setSessionMode(session: SessionRecord, modeId: string): Promise<void>;
  setSessionConfigOption(
    session: SessionRecord,
    request: SessionConfigRequest,
  ): Promise<unknown>;
  replyPermission(
    requestId: string,
    outcome: acp.RequestPermissionOutcome,
  ): boolean;
  replyQuestion(
    requestId: string,
    answers: Record<string, string[]> | null,
  ): boolean;
}

export function toStoredJson(value: unknown): JsonValue {
  return JSON.parse(JSON.stringify(value ?? null)) as JsonValue;
}

export function extractPromptText(prompt: acp.ContentBlock[]) {
  return prompt
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
}

export function parseStoredSessionCapabilities(
  capabilitiesJson: string | null,
): StoredSessionCapabilities {
  if (!capabilitiesJson) {
    return {};
  }

  try {
    const parsed = JSON.parse(capabilitiesJson) as StoredSessionCapabilities;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {};
    }
    return parsed;
  } catch {
    return {};
  }
}

export function buildStoredSessionCapabilities(
  current: StoredSessionCapabilities,
  updates: StoredSessionCapabilities,
): StoredSessionCapabilities {
  return {
    authMethods:
      updates.authMethods === undefined
        ? (current.authMethods ?? null)
        : updates.authMethods,
    agentCapabilities:
      updates.agentCapabilities === undefined
        ? (current.agentCapabilities ?? null)
        : updates.agentCapabilities,
    availableCommands:
      updates.availableCommands === undefined
        ? (current.availableCommands ?? null)
        : updates.availableCommands,
    configOptions:
      updates.configOptions === undefined
        ? (current.configOptions ?? null)
        : updates.configOptions,
    models:
      updates.models === undefined ? (current.models ?? null) : updates.models,
    modes: updates.modes === undefined ? (current.modes ?? null) : updates.modes,
  };
}

export function getAgentLaunchMetadata(metadataJson: string | null): AgentLaunchMetadata {
  if (!metadataJson) {
    return { args: [], env: {} };
  }

  try {
    const metadata = JSON.parse(metadataJson) as Record<string, unknown>;
    const args = Array.isArray(metadata.args)
      ? metadata.args.filter((entry): entry is string => typeof entry === "string")
      : [];
    const envEntries =
      metadata.env && typeof metadata.env === "object" && !Array.isArray(metadata.env)
        ? Object.entries(metadata.env).filter(
            (entry): entry is [string, string] => typeof entry[1] === "string",
          )
        : [];
    return {
      args,
      env: Object.fromEntries(envEntries),
    };
  } catch {
    return { args: [], env: {} };
  }
}

export function buildModeState(
  modes: Array<{ id: string; name: string; description?: string | null }>,
  currentModeId: string,
): acp.SessionModeState {
  return {
    availableModes: modes.map((mode) => ({
      id: mode.id,
      name: mode.name,
      description: mode.description ?? null,
    })),
    currentModeId,
  };
}

export function buildSelectConfigOption(input: {
  id: string;
  name: string;
  currentValue: string;
  choices: Array<{
    value: string;
    name: string;
    description?: string | null;
    group?: string | null;
  }>;
  category?: string | null;
  description?: string | null;
}): acp.SessionConfigOption {
  const options: Array<{
    value: string;
    name: string;
    description?: string | null;
  }> = input.choices.map((choice) => ({
      value: choice.value,
      name:
        choice.group && choice.group.trim().length > 0
          ? `${choice.group} / ${choice.name}`
          : choice.name,
      description: choice.description ?? null,
    }));

  return {
    type: "select",
    id: input.id,
    name: input.name,
    category: input.category ?? null,
    description: input.description ?? null,
    currentValue: input.currentValue,
    options,
  };
}

export function buildBooleanConfigOption(input: {
  id: string;
  name: string;
  currentValue: boolean;
  category?: string | null;
  description?: string | null;
}): acp.SessionConfigOption {
  return {
    type: "boolean",
    id: input.id,
    name: input.name,
    category: input.category ?? null,
    description: input.description ?? null,
    currentValue: input.currentValue,
  };
}

export function updateConfigOptions(
  current: acp.SessionConfigOption[] | null | undefined,
  request: SessionConfigRequest,
): acp.SessionConfigOption[] {
  return (current ?? []).map((option) => {
    if (option.id !== request.configId) {
      return option;
    }

    if (request.type === "boolean" && option.type === "boolean") {
      return {
        ...option,
        currentValue: request.value,
      };
    }

    if (request.type === "value" && option.type === "select") {
      return {
        ...option,
        currentValue: request.value,
      };
    }

    return option;
  });
}

export function getSelectConfigValue(
  configOptions: acp.SessionConfigOption[] | null | undefined,
  configId: string,
): string | null {
  const option = (configOptions ?? []).find(
    (entry) => entry.id === configId && entry.type === "select",
  );
  return option?.type === "select" ? option.currentValue : null;
}

export function getBooleanConfigValue(
  configOptions: acp.SessionConfigOption[] | null | undefined,
  configId: string,
): boolean | null {
  const option = (configOptions ?? []).find(
    (entry) => entry.id === configId && entry.type === "boolean",
  );
  return option?.type === "boolean" ? option.currentValue : null;
}

export function buildStandardPermissionRequest(input: {
  toolCallId: string;
  kind: string;
  title: string;
  rawInput?: unknown;
  metadata?: JsonObject;
  allowAlways?: boolean;
}): JsonObject {
  return {
    toolCall: {
      toolCallId: input.toolCallId,
      kind: input.kind,
      title: input.title,
      ...(input.rawInput === undefined ? {} : { rawInput: toStoredJson(input.rawInput) }),
    },
    ...(input.metadata ? { metadata: input.metadata } : {}),
    options: [
      {
        optionId: "allow_once",
        kind: "allow_once",
        name: "Allow once",
      },
      ...(input.allowAlways === false
        ? []
        : [
            {
              optionId: "allow_always",
              kind: "allow_always",
              name: "Always allow",
            },
          ]),
      {
        optionId: "reject_once",
        kind: "reject_once",
        name: "Reject",
      },
    ],
  };
}

export function agentSessionIdFromSnapshot(snapshot: SessionSnapshot | null) {
  return snapshot?.session.agentSessionId ?? null;
}

export abstract class NativeRuntimeBase {
  protected readonly bindingsByAgentSession = new Map<string, RuntimeSessionBinding>();
  protected readonly bindingsByLocalSession = new Map<string, RuntimeSessionBinding>();
  private readonly pendingPermissions = new Map<string, PendingPermissionHandler>();
  private readonly pendingQuestions = new Map<string, PendingQuestionHandler>();
  protected readonly logger: Logger;

  constructor(
    readonly agentId: string,
    protected readonly db: StateDatabase,
    protected readonly paths: StatePaths,
    protected readonly broadcast: (sessionId: string, event: BroadcastEvent) => void,
    parentLogger: Logger,
  ) {
    this.logger = parentLogger.child({ agentId });
  }

  listAuthMethods(): acp.AuthMethod[] {
    return [];
  }

  getCapabilities(): acp.AgentCapabilities | null {
    return null;
  }

  supportsSessionListing() {
    return false;
  }

  async authenticate(
    _params: acp.AuthenticateRequest,
  ): Promise<acp.AuthenticateResponse> {
    throw new Error(`Authentication is not supported for ${this.agentId}.`);
  }

  protected bindSession(
    localSessionId: string,
    agentSessionId: string,
    loaded = true,
  ) {
    const binding = {
      localSessionId,
      agentSessionId,
      loaded,
    } satisfies RuntimeSessionBinding;
    this.bindingsByAgentSession.set(agentSessionId, binding);
    this.bindingsByLocalSession.set(localSessionId, binding);
    return binding;
  }

  protected rebindSession(localSessionId: string, nextAgentSessionId: string) {
    const existing = this.bindingsByLocalSession.get(localSessionId);
    if (existing) {
      this.bindingsByAgentSession.delete(existing.agentSessionId);
    }
    const updated = this.bindSession(localSessionId, nextAgentSessionId, true);
    this.db.updateSession(localSessionId, {
      agentSessionId: nextAgentSessionId,
    });
    return updated;
  }

  protected updateStoredCapabilities(
    sessionId: string,
    updates: StoredSessionCapabilities,
  ) {
    const session = this.db.getSession(sessionId);
    if (!session) {
      return;
    }
    const current = parseStoredSessionCapabilities(session.capabilitiesJson);
    const next = buildStoredSessionCapabilities(current, updates);
    this.db.updateSession(sessionId, {
      capabilities: toStoredJson(next),
    });
  }

  protected createSessionRecord(input: {
    project: ProjectRecord;
    controllerDeviceId: string | null;
    agentSessionId: string;
    cwd?: string;
    title?: string | null;
    status?: string;
    capabilities?: StoredSessionCapabilities;
  }) {
    const session = this.db.createSession({
      projectId: input.project.id,
      agentId: this.agentId,
      agentSessionId: input.agentSessionId,
      cwd: input.cwd ?? input.project.rootPath,
      title: input.title ?? null,
      status: input.status ?? "idle",
      controllerDeviceId: input.controllerDeviceId,
      capabilities:
        input.capabilities === undefined
          ? undefined
          : toStoredJson(input.capabilities),
    });
    this.bindSession(session.id, input.agentSessionId, true);
    return session;
  }

  protected emitSessionEntry(
    sessionId: string,
    kind: string,
    payload: JsonObject,
  ) {
    const entry = this.db.appendSessionEntry(sessionId, kind, payload);
    this.broadcast(sessionId, {
      type: "session_update",
      payload: {
        sessionId,
        entry: toStoredJson(entry) as JsonValue,
      },
    });
    return entry;
  }

  protected emitPermissionRequest(
    sessionId: string,
    request: JsonObject,
    handler: (outcome: acp.RequestPermissionOutcome) => Promise<void> | void,
  ) {
    const requestId = randomUUID();
    this.pendingPermissions.set(requestId, {
      localSessionId: sessionId,
      handler,
    });
    this.broadcast(sessionId, {
      type: "permission_request",
      payload: {
        requestId,
        sessionId,
        request: toStoredJson(request),
      },
    });
    return requestId;
  }

  protected clearSessionPermissions(sessionId: string) {
    for (const [requestId, pending] of this.pendingPermissions.entries()) {
      if (pending.localSessionId !== sessionId) {
        continue;
      }
      this.pendingPermissions.delete(requestId);
      void Promise.resolve(
        pending.handler({
          outcome: "cancelled",
        }),
      ).catch((error) => {
        this.logger.warn("failed to cancel pending permission", {
          requestId,
          error: error instanceof Error ? error.message : String(error),
        });
      });
    }
  }

  protected emitQuestionRequest(
    sessionId: string,
    request: JsonObject,
    handler: (answers: Record<string, string[]> | null) => Promise<void> | void,
  ) {
    const requestId = randomUUID();
    this.pendingQuestions.set(requestId, {
      localSessionId: sessionId,
      handler,
    });
    this.broadcast(sessionId, {
      type: "question_request",
      payload: {
        requestId,
        sessionId,
        request: toStoredJson(request),
      },
    });
    return requestId;
  }

  protected clearSessionQuestions(sessionId: string) {
    for (const [requestId, pending] of this.pendingQuestions.entries()) {
      if (pending.localSessionId !== sessionId) {
        continue;
      }
      this.pendingQuestions.delete(requestId);
      void Promise.resolve(pending.handler(null)).catch((error) => {
        this.logger.warn("failed to cancel pending question", {
          requestId,
          error: error instanceof Error ? error.message : String(error),
        });
      });
    }
  }

  replyPermission(
    requestId: string,
    outcome: acp.RequestPermissionOutcome,
  ): boolean {
    const pending = this.pendingPermissions.get(requestId);
    if (!pending) {
      return false;
    }
    this.pendingPermissions.delete(requestId);
    void Promise.resolve(pending.handler(outcome)).catch((error) => {
      this.logger.warn("failed to deliver permission reply", {
        requestId,
        error: error instanceof Error ? error.message : String(error),
      });
    });
    return true;
  }

  replyQuestion(
    requestId: string,
    answers: Record<string, string[]> | null,
  ): boolean {
    const pending = this.pendingQuestions.get(requestId);
    if (!pending) {
      return false;
    }
    this.pendingQuestions.delete(requestId);
    void Promise.resolve(pending.handler(answers)).catch((error) => {
      this.logger.warn("failed to deliver question reply", {
        requestId,
        error: error instanceof Error ? error.message : String(error),
      });
    });
    return true;
  }

  protected normalizePrompt(prompt: acp.ContentBlock[]) {
    return {
      prompt: toStoredJson(prompt),
      text: extractPromptText(prompt),
    };
  }
}
