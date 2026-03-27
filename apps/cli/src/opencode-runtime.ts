import { spawn } from "node:child_process";

import * as acp from "@agentclientprotocol/sdk";

import {
  NativeRuntimeBase,
  type RuntimeSessionBinding,
  buildModeState,
  buildSelectConfigOption,
  getAgentLaunchMetadata,
  parseStoredSessionCapabilities,
  toStoredJson,
  updateConfigOptions,
  type RuntimeListSessionsResponse,
  type SessionConfigRequest,
  type StoredSessionCapabilities,
} from "./native-runtime-support";
import {
  buildSessionDiffEntry,
  normalizeFileDiff,
} from "./session-derived-state";
import type { JsonObject, JsonValue, ProjectRecord, SessionRecord } from "./types";

type OpenCodeSession = {
  id: string;
  directory: string;
  title?: string | null;
  time?: {
    created?: number;
    updated?: number;
  };
};

type OpenCodeMessage = {
  info?: Record<string, unknown>;
  parts?: Array<Record<string, unknown>>;
};

type PartMeta = {
  role: string | null;
  type: string;
  emittedText: string;
};

type PendingPrompt = {
  resolve: (value: { stopReason: string }) => void;
  reject: (error: Error) => void;
};

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function asObject(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function toIsoFromMillis(value: unknown) {
  const millis = asNumber(value);
  return millis === null ? null : new Date(millis).toISOString();
}

function normalizeToolStatus(status: string | null) {
  switch (status) {
    case "completed":
      return "completed";
    case "error":
    case "failed":
      return "failed";
    case "running":
    case "in_progress":
      return "in_progress";
    default:
      return "pending";
  }
}

function buildTextContent(text: string): JsonObject {
  return {
    type: "text",
    text,
  };
}

function findTextDelta(previous: string, current: string) {
  if (!current.startsWith(previous)) {
    return current;
  }
  return current.slice(previous.length);
}

function stringifyUnknown(value: unknown) {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function buildTodoPlanEntry(todos: unknown[]): JsonObject {
  return {
    kind: "plan",
    update: {
      entries: todos
        .map((todo) => asObject(todo))
        .filter((todo): todo is Record<string, unknown> => todo !== null)
        .map((todo) => ({
          content: asString(todo.content) ?? "",
          status: asString(todo.status) ?? "pending",
        })),
    },
  };
}

export class OpenCodeRuntime extends NativeRuntimeBase {
  private child: ReturnType<typeof spawn> | null = null;
  private baseUrl: string | null = null;
  private startPromise: Promise<void> | null = null;
  private eventAbort: AbortController | null = null;
  private readonly partMetaById = new Map<string, PartMeta>();
  private readonly sessionStopReasons = new Map<string, string>();
  private readonly pendingPrompts = new Map<string, PendingPrompt>();
  private readonly seenToolParts = new Set<string>();

  listAuthMethods(): acp.AuthMethod[] {
    return [];
  }

  getCapabilities(): acp.AgentCapabilities | null {
    return {
      loadSession: true,
      promptCapabilities: {
        image: false,
        audio: false,
        embeddedContext: true,
      },
      sessionCapabilities: {
        list: {},
      },
    };
  }

  supportsSessionListing() {
    return true;
  }

  async ensureStarted(): Promise<void> {
    if (this.baseUrl) {
      return;
    }

    if (this.startPromise) {
      await this.startPromise;
      return;
    }

    this.startPromise = this.startServer();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = null;
    }
  }

  private async startServer() {
    const agent = this.db.getAgent(this.agentId);
    const launch = getAgentLaunchMetadata(agent?.metadataJson ?? null);

    if (!agent?.binaryPath) {
      throw new Error(`Agent ${this.agentId} is unavailable on this machine.`);
    }

    const child = spawn(agent.binaryPath, launch.args, {
      stdio: ["ignore", "pipe", "pipe"],
      cwd: process.cwd(),
      env: {
        ...process.env,
        ...launch.env,
      },
    });

    const url = await new Promise<string>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Timed out waiting for OpenCode server URL."));
      }, 10_000);

      const handleOutput = (chunk: Buffer | string) => {
        const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
        const match = text.match(/http:\/\/127\.0\.0\.1:\d+/);
        if (match) {
          clearTimeout(timeout);
          resolve(match[0]);
        }
      };

      child.stdout.on("data", handleOutput);
      child.stderr.on("data", handleOutput);
      child.once("error", reject);
      child.once("exit", (code) => {
        clearTimeout(timeout);
        reject(new Error(`OpenCode server exited before becoming ready (${code ?? "unknown"}).`));
      });
    });

    this.child = child;
    this.baseUrl = url;

    child.on("exit", (code, signal) => {
      this.logger.warn("OpenCode server exited", {
        code,
        signal,
      });
      this.child = null;
      this.baseUrl = null;
      this.eventAbort?.abort();
      this.eventAbort = null;
    });

    for (let attempt = 0; attempt < 30; attempt += 1) {
      try {
        const response = await fetch(`${url}/global/health`);
        if (response.ok) {
          break;
        }
      } catch {}
      await sleep(200);
    }

    this.eventAbort = new AbortController();
    void this.runEventStream(this.eventAbort.signal);
  }

  private async runEventStream(signal: AbortSignal) {
    while (!signal.aborted && this.baseUrl) {
      try {
        const response = await fetch(`${this.baseUrl}/event`, { signal });
        if (!response.ok || !response.body) {
          throw new Error(`OpenCode event stream failed (${response.status}).`);
        }

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (!signal.aborted) {
          const { value, done } = await reader.read();
          if (done) {
            break;
          }

          buffer += decoder.decode(value, { stream: true });
          let separator = buffer.indexOf("\n\n");
          while (separator >= 0) {
            const rawEvent = buffer.slice(0, separator);
            buffer = buffer.slice(separator + 2);
            separator = buffer.indexOf("\n\n");

            const data = rawEvent
              .split(/\n/)
              .filter((line) => line.startsWith("data:"))
              .map((line) => line.slice(5).trim())
              .join("\n");

            if (!data) {
              continue;
            }

            try {
              const parsed = JSON.parse(data) as Record<string, unknown>;
              const payload =
                asObject(parsed.payload) && asString(parsed.directory)
                  ? asObject(parsed.payload)
                  : parsed;
              if (payload) {
                this.handleEvent(payload);
              }
            } catch (error) {
              this.logger.warn("failed to parse OpenCode SSE event", {
                error: error instanceof Error ? error.message : String(error),
                data,
              });
            }
          }
        }
      } catch (error) {
        if (signal.aborted) {
          return;
        }
        this.logger.warn("OpenCode event stream disconnected", {
          error: error instanceof Error ? error.message : String(error),
        });
        await sleep(500);
      }
    }
  }

  private async requestJson(
    method: string,
    path: string,
    options: {
      cwd?: string;
      body?: JsonValue | null;
    } = {},
  ): Promise<unknown> {
    await this.ensureStarted();
    if (!this.baseUrl) {
      throw new Error("OpenCode server is unavailable.");
    }

    const url = new URL(path, this.baseUrl);
    if (options.cwd) {
      url.searchParams.set("directory", options.cwd);
    }

    const response = await fetch(url, {
      method,
      headers:
        options.body === undefined
          ? undefined
          : {
              "content-type": "application/json",
            },
      body:
        options.body === undefined
          ? undefined
          : options.body === null
            ? "null"
            : JSON.stringify(options.body),
    });

    const text = await response.text();
    if (!response.ok) {
      throw new Error(
        `OpenCode request failed (${response.status} ${response.statusText}): ${text}`,
      );
    }

    if (!text.trim()) {
      return null;
    }

    return JSON.parse(text) as unknown;
  }

  private async fetchModes(cwd: string) {
    const response = await this.requestJson("GET", "/agent", { cwd });
    const agents = asArray(response)
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null)
      .filter((entry) => asString(entry.mode) === "primary");

    const modes = agents.map((entry) => ({
      id: asString(entry.name) ?? "build",
      name: asString(entry.name) ?? "build",
      description: asString(entry.description),
    }));

    const currentModeId =
      modes.find((mode) => mode.id === "build")?.id ?? modes[0]?.id ?? "build";

    return buildModeState(modes.length > 0 ? modes : [{ id: "build", name: "build" }], currentModeId);
  }

  private async fetchModelState(cwd: string) {
    const response = asObject(await this.requestJson("GET", "/provider", { cwd }));
    const allProviders = asArray(response?.all)
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null);
    const defaults = asObject(response?.default) ?? {};
    const connected = new Set(
      asArray(response?.connected)
        .map((entry) => asString(entry))
        .filter((entry): entry is string => entry !== null),
    );

    const availableModels: acp.ModelInfo[] = [];
    const selectChoices: Array<{
      value: string;
      name: string;
      description?: string | null;
      group?: string | null;
    }> = [];
    let currentModelId: string | null = null;

    for (const provider of allProviders) {
      const providerId = asString(provider.id);
      const providerName = asString(provider.name) ?? providerId;
      const models = asObject(provider.models);
      if (!providerId || !models) {
        continue;
      }

      if (connected.size > 0 && !connected.has(providerId) && defaults[providerId] === undefined) {
        continue;
      }

      for (const model of Object.values(models)) {
        const modelInfo = asObject(model);
        const modelId = asString(modelInfo?.id);
        const modelName = asString(modelInfo?.name) ?? modelId ?? "Model";
        const capabilities = asObject(modelInfo?.capabilities);
        const input = asObject(capabilities?.input);
        if (!modelId || input?.text !== true) {
          continue;
        }

        const compositeId = JSON.stringify([providerId, modelId]);
        availableModels.push({
          modelId: compositeId,
          name: `${providerName ?? providerId} / ${modelName}`,
          description: asString(modelInfo?.family),
        });
        selectChoices.push({
          value: compositeId,
          name: modelName,
          description: asString(modelInfo?.family),
          group: providerName ?? providerId,
        });

        if (defaults[providerId] === modelId && !currentModelId) {
          currentModelId = compositeId;
        }
      }
    }

    if (!currentModelId && availableModels[0]) {
      currentModelId = availableModels[0].modelId;
    }

    const configOption =
      currentModelId && selectChoices.length > 0
        ? buildSelectConfigOption({
            id: "model",
            name: "Model",
            category: "model",
            currentValue: currentModelId,
            choices: selectChoices,
          })
        : null;

    return {
      models:
        currentModelId && availableModels.length > 0
          ? {
              availableModels,
              currentModelId,
            }
          : null,
      configOption,
    };
  }

  private async buildSessionCapabilities(cwd: string): Promise<StoredSessionCapabilities> {
    const [modes, modelState] = await Promise.all([
      this.fetchModes(cwd),
      this.fetchModelState(cwd),
    ]);

    return {
      authMethods: [],
      agentCapabilities: this.getCapabilities(),
      availableCommands: [],
      modes,
      models: modelState.models,
      configOptions: modelState.configOption ? [modelState.configOption] : [],
    };
  }

  async createSession(
    project: ProjectRecord,
    controllerDeviceId: string | null,
  ): Promise<SessionRecord> {
    const response = asObject(
      await this.requestJson("POST", "/session", {
        cwd: project.rootPath,
      }),
    );

    const agentSessionId = asString(response?.id);
    if (!agentSessionId) {
      throw new Error("OpenCode did not return a session ID.");
    }

    const capabilities = await this.buildSessionCapabilities(project.rootPath);
    return this.createSessionRecord({
      project,
      controllerDeviceId,
      agentSessionId,
      cwd: asString(response?.directory) ?? project.rootPath,
      title: asString(response?.title),
      capabilities,
    });
  }

  async ensureSessionLoaded(
    session: SessionRecord,
  ): Promise<RuntimeSessionBinding | null> {
    await this.ensureStarted();

    const existing = this.bindingsByLocalSession.get(session.id);
    if (existing?.loaded) {
      return existing;
    }

    const binding = existing ?? this.bindSession(session.id, session.agentSessionId, false);

    if (
      !session.capabilitiesJson ||
      !parseStoredSessionCapabilities(session.capabilitiesJson).modes
    ) {
      this.updateStoredCapabilities(
        session.id,
        await this.buildSessionCapabilities(session.cwd),
      );
    }

    if (this.db.listSessionEntries(session.id).length === 0) {
      await this.hydrateSession(session);
    }

    binding.loaded = true;
    return binding;
  }

  async promptSession(
    session: SessionRecord,
    prompt: acp.ContentBlock[],
  ): Promise<Record<string, unknown>> {
    await this.ensureSessionLoaded(session);
    const promptState = this.normalizePrompt(prompt);

    this.db.updateSession(session.id, {
      status: "running",
      lastStopReason: null,
    });

    this.emitSessionEntry(session.id, "user_message", {
      kind: "user_message",
      prompt: promptState.prompt,
      text: promptState.text,
    });

    const capabilities = parseStoredSessionCapabilities(
      this.db.getSession(session.id)?.capabilitiesJson ?? session.capabilitiesJson,
    );
    const currentModeId = capabilities.modes?.currentModeId ?? "build";
    const currentModelId = capabilities.models?.currentModelId ?? null;
    const modelTuple =
      typeof currentModelId === "string"
        ? (JSON.parse(currentModelId) as [string, string])
        : null;

    const completion = new Promise<{ stopReason: string }>((resolve, reject) => {
      this.pendingPrompts.set(session.id, { resolve, reject });
    });

    try {
      await this.requestJson("POST", `/session/${encodeURIComponent(session.agentSessionId)}/message`, {
        cwd: session.cwd,
        body: {
          parts: [
            {
              type: "text",
              text: promptState.text,
            },
          ],
          agent: currentModeId,
          ...(Array.isArray(modelTuple) && modelTuple.length === 2
            ? {
                model: {
                  providerID: modelTuple[0],
                  modelID: modelTuple[1],
                },
              }
            : {}),
        },
      });

      const result = await completion;
      this.db.updateSession(session.id, {
        status: "idle",
        lastStopReason: result.stopReason,
      });
      return result;
    } catch (error) {
      this.pendingPrompts.delete(session.id);
      this.db.updateSession(session.id, {
        status: "idle",
        lastStopReason: "failed",
      });
      throw error;
    }
  }

  async cancelSession(session: SessionRecord): Promise<void> {
    this.clearSessionPermissions(session.id);
    this.clearSessionQuestions(session.id);
    this.pendingPrompts.get(session.id)?.resolve({ stopReason: "cancelled" });
    this.pendingPrompts.delete(session.id);
    this.db.updateSession(session.id, {
      status: "idle",
      lastStopReason: "cancelled",
    });
  }

  async listSessions(cwd: string): Promise<RuntimeListSessionsResponse> {
    const response = asArray(await this.requestJson("GET", "/session", { cwd }));
    const sessions = response
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null)
      .map((entry) => ({
        sessionId: asString(entry.id) ?? "",
        cwd: asString(entry.directory) ?? cwd,
        title: asString(entry.title),
        updatedAt: toIsoFromMillis(asObject(entry.time)?.updated),
      }))
      .filter((entry) => entry.sessionId.length > 0);

    return { sessions };
  }

  async setSessionMode(session: SessionRecord, modeId: string): Promise<void> {
    const current = parseStoredSessionCapabilities(session.capabilitiesJson);
    this.updateStoredCapabilities(session.id, {
      modes: {
        availableModes: current.modes?.availableModes ?? [],
        currentModeId: modeId,
      },
    });
    this.emitSessionEntry(session.id, "current_mode_update", {
      kind: "current_mode_update",
      update: {
        sessionUpdate: "current_mode_update",
        currentModeId: modeId,
      },
    });
  }

  async setSessionConfigOption(
    session: SessionRecord,
    request: SessionConfigRequest,
  ): Promise<unknown> {
    const current = parseStoredSessionCapabilities(session.capabilitiesJson);
    const nextConfigOptions = updateConfigOptions(current.configOptions, request);
    const nextModels =
      request.type === "value" && request.configId === "model"
        ? {
            availableModels: current.models?.availableModels ?? [],
            currentModelId: request.value,
          }
        : current.models ?? null;

    this.updateStoredCapabilities(session.id, {
      configOptions: nextConfigOptions,
      models: nextModels,
    });

    this.emitSessionEntry(session.id, "config_option_update", {
      kind: "config_option_update",
      update: {
        sessionUpdate: "config_option_update",
        configOptions: toStoredJson(nextConfigOptions),
      },
    });

    return {
      configOptions: nextConfigOptions,
    };
  }

  private async hydrateSession(session: SessionRecord) {
    try {
      const sessionInfo = asObject(
        await this.requestJson(
          "GET",
          `/session/${encodeURIComponent(session.agentSessionId)}`,
          { cwd: session.cwd },
        ),
      );
      if (sessionInfo) {
        this.db.updateSession(session.id, {
          title: asString(sessionInfo.title),
        });
      }

      const messages = asArray(
        await this.requestJson(
          "GET",
          `/session/${encodeURIComponent(session.agentSessionId)}/message`,
          { cwd: session.cwd },
        ),
      );
      for (const message of messages) {
        this.ingestHistoricalMessage(session.id, asObject(message));
      }

      const todos = asArray(
        await this.requestJson(
          "GET",
          `/session/${encodeURIComponent(session.agentSessionId)}/todo`,
          { cwd: session.cwd },
        ),
      );
      if (todos.length > 0) {
        this.db.appendSessionEntry(session.id, "plan", buildTodoPlanEntry(todos));
      }

      const diffs = asArray(
        await this.requestJson(
          "GET",
          `/session/${encodeURIComponent(session.agentSessionId)}/diff`,
          { cwd: session.cwd },
        ),
      )
        .map(normalizeFileDiff)
        .filter((diff): diff is NonNullable<ReturnType<typeof normalizeFileDiff>> => diff !== null);
      if (diffs.length > 0) {
        this.db.appendSessionEntry(
          session.id,
          "session_diff_update",
          buildSessionDiffEntry(diffs),
        );
      }
    } catch (error) {
      this.logger.warn("failed to hydrate OpenCode session", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private ingestHistoricalMessage(
    localSessionId: string,
    message: Record<string, unknown> | null,
  ) {
    if (!message) {
      return;
    }

    const info = asObject(message.info);
    const role = asString(info?.role);
    const parts = asArray(message.parts)
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null);

    if (role === "user") {
      const text = parts
        .filter((part) => asString(part.type) === "text")
        .map((part) => asString(part.text) ?? "")
        .join("\n")
        .trim();
      if (text) {
        this.db.appendSessionEntry(localSessionId, "user_message", {
          kind: "user_message",
          text,
          prompt: [
            {
              type: "text",
              text,
            },
          ],
        });
      }
      return;
    }

    if (role !== "assistant") {
      return;
    }

    for (const part of parts) {
      this.ingestAssistantPart(localSessionId, part, false, role);
    }
  }

  private ensureBoundLocalSession(agentSessionId: string) {
    const existing = this.bindingsByAgentSession.get(agentSessionId);
    if (existing) {
      return existing.localSessionId;
    }

    const session = this.db.getSessionByAgentSessionForAgent(this.agentId, agentSessionId);
    if (!session) {
      return null;
    }

    this.bindSession(session.id, agentSessionId, true);
    return session.id;
  }

  private handleEvent(event: Record<string, unknown>) {
    const type = asString(event.type);
    const properties = asObject(event.properties) ?? {};
    if (!type) {
      return;
    }

    switch (type) {
      case "session.created":
      case "session.updated": {
        const info = asObject(properties.info);
        const agentSessionId = asString(info?.id);
        if (!agentSessionId) {
          return;
        }
        const localSessionId = this.ensureBoundLocalSession(agentSessionId);
        if (!localSessionId) {
          return;
        }
        const title = asString(info?.title);
        if (title !== null) {
          this.db.updateSession(localSessionId, { title });
          this.emitSessionEntry(localSessionId, "session_info_update", {
            kind: "session_info_update",
            update: {
              sessionUpdate: "session_info_update",
              title,
              updatedAt: toIsoFromMillis(asObject(info?.time)?.updated),
            },
          });
        }
        return;
      }
      case "session.status": {
        const sessionId = asString(properties.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        const statusType = asString(asObject(properties.status)?.type);
        this.db.updateSession(localSessionId, {
          status: statusType === "idle" ? "idle" : "running",
        });
        return;
      }
      case "session.idle": {
        const sessionId = asString(properties.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        const stopReason = this.sessionStopReasons.get(localSessionId) ?? "completed";
        this.pendingPrompts.get(localSessionId)?.resolve({ stopReason });
        this.pendingPrompts.delete(localSessionId);
        return;
      }
      case "session.error": {
        const sessionId = asString(properties.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        const errorInfo = asObject(properties.error);
        const message =
          asString(asObject(errorInfo?.data)?.message) ??
          asString(errorInfo?.name) ??
          "OpenCode session failed.";
        this.sessionStopReasons.set(localSessionId, "failed");
        this.pendingPrompts.get(localSessionId)?.reject(new Error(message));
        this.pendingPrompts.delete(localSessionId);
        this.db.updateSession(localSessionId, {
          status: "idle",
          lastStopReason: "failed",
        });
        return;
      }
      case "todo.updated": {
        const sessionId = asString(properties.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        this.emitSessionEntry(localSessionId, "plan", buildTodoPlanEntry(asArray(properties.todos)));
        return;
      }
      case "session.diff": {
        const sessionId = asString(properties.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        const diffs = asArray(properties.diff)
          .map(normalizeFileDiff)
          .filter((diff): diff is NonNullable<ReturnType<typeof normalizeFileDiff>> => diff !== null);
        this.emitSessionEntry(
          localSessionId,
          "session_diff_update",
          buildSessionDiffEntry(diffs),
        );
        return;
      }
      case "message.updated": {
        const info = asObject(properties.info);
        const sessionId = asString(info?.sessionID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId) {
          return;
        }
        const role = asString(info?.role);
        const messageId = asString(info?.id);
        if (messageId && role) {
          this.partMetaById.set(`message:${messageId}`, {
            role,
            type: "message",
            emittedText: "",
          });
        }

        const title = asString(asObject(info?.path)?.root);
        void title;

        const mode = asString(info?.mode) ?? asString(info?.agent);
        if (mode) {
          const session = this.db.getSession(localSessionId);
          if (session) {
            const capabilities = parseStoredSessionCapabilities(session.capabilitiesJson);
            if (capabilities.modes?.currentModeId !== mode) {
              this.updateStoredCapabilities(localSessionId, {
                modes: {
                  availableModes: capabilities.modes?.availableModes ?? [],
                  currentModeId: mode,
                },
              });
            }
          }
        }

        return;
      }
      case "message.part.delta": {
        const sessionId = asString(properties.sessionID);
        const partId = asString(properties.partID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        const delta = asString(properties.delta);
        if (!localSessionId || !partId || !delta) {
          return;
        }
        const meta = this.partMetaById.get(partId);
        if (!meta || meta.role !== "assistant") {
          return;
        }
        meta.emittedText += delta;
        if (meta.type === "text") {
          this.emitSessionEntry(localSessionId, "agent_message_chunk", {
            kind: "agent_message_chunk",
            content: buildTextContent(delta),
          });
        } else if (meta.type === "reasoning") {
          this.emitSessionEntry(localSessionId, "agent_thought_chunk", {
            kind: "agent_thought_chunk",
            content: buildTextContent(delta),
          });
        }
        return;
      }
      case "message.part.updated": {
        const part = asObject(properties.part);
        const sessionId = asString(part?.sessionID);
        const messageId = asString(part?.messageID);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId || !part || !messageId) {
          return;
        }
        const messageMeta = this.partMetaById.get(`message:${messageId}`);
        this.ingestAssistantPart(localSessionId, part, true, messageMeta?.role ?? null);
        return;
      }
      case "permission.updated": {
        const sessionId = asString(properties.sessionID);
        const permissionId = asString(properties.id);
        const localSessionId = sessionId ? this.ensureBoundLocalSession(sessionId) : null;
        if (!localSessionId || !permissionId) {
          return;
        }
        const request = this.buildPermissionRequest(properties);
        this.emitPermissionRequest(localSessionId, request, async (outcome) => {
          const response =
            outcome.outcome === "selected" && outcome.optionId === "reject_once"
              ? "reject"
              : outcome.outcome === "selected" && outcome.optionId === "allow_always"
                ? "always"
                : "once";

          await this.requestJson(
            "POST",
            `/session/${encodeURIComponent(sessionId ?? "")}/permissions/${encodeURIComponent(permissionId)}`,
            {
              cwd: this.db.getSession(localSessionId)?.cwd,
              body: {
                response,
              },
            },
          );
        });
        return;
      }
      default:
        return;
    }
  }

  private buildPermissionRequest(properties: Record<string, unknown>) {
    return {
      toolCall: {
        toolCallId: asString(properties.callID) ?? asString(properties.id) ?? "permission",
        kind: asString(properties.type) ?? "permission",
        title: asString(properties.title) ?? "Permission request",
        rawInput: toStoredJson(asObject(properties.metadata) ?? {}),
      },
      options: [
        {
          optionId: "allow_once",
          kind: "allow_once",
          name: "Allow once",
        },
        {
          optionId: "allow_always",
          kind: "allow_always",
          name: "Always allow",
        },
        {
          optionId: "reject_once",
          kind: "reject_once",
          name: "Reject",
        },
      ],
    } satisfies JsonObject;
  }

  private ingestAssistantPart(
    localSessionId: string,
    part: Record<string, unknown>,
    broadcast: boolean,
    role: string | null,
  ) {
    const type = asString(part.type);
    const partId = asString(part.id);
    if (!type || !partId) {
      return;
    }

    const meta = this.partMetaById.get(partId) ?? {
      role,
      type,
      emittedText: "",
    };
    meta.role = role;
    meta.type = type;
    this.partMetaById.set(partId, meta);

    const append = (kind: string, payload: JsonObject) => {
      if (broadcast) {
        this.emitSessionEntry(localSessionId, kind, payload);
      } else {
        this.db.appendSessionEntry(localSessionId, kind, payload);
      }
    };

    if (role !== "assistant") {
      return;
    }

    if (type === "text" || type === "reasoning") {
      const currentText = asString(part.text) ?? "";
      const delta = findTextDelta(meta.emittedText, currentText);
      meta.emittedText = currentText;
      if (!delta) {
        return;
      }
      append(type === "text" ? "agent_message_chunk" : "agent_thought_chunk", {
        kind: type === "text" ? "agent_message_chunk" : "agent_thought_chunk",
        content: buildTextContent(delta),
      });
      return;
    }

    if (type === "tool") {
      const state = asObject(part.state) ?? {};
      const toolCallId = asString(part.callID) ?? partId;
      const entryKind = this.seenToolParts.has(partId) ? "tool_call_update" : "tool_call";
      this.seenToolParts.add(partId);
      append(entryKind, {
        kind: entryKind,
        update: {
          toolCallId,
          kind: asString(part.tool) ?? "tool",
          title: asString(state.title) ?? asString(part.tool) ?? "tool",
          status: normalizeToolStatus(asString(state.status)),
          rawInput:
            toStoredJson(state.input) ??
            (typeof state.raw === "string"
              ? {
                  raw: state.raw,
                }
              : {}),
          rawOutput:
            asString(state.output) ??
            asString(state.error) ??
            stringifyUnknown(state.output ?? state.error),
          metadata: toStoredJson(asObject(state.metadata) ?? {}),
        },
      });
      return;
    }

    if (type === "step-finish") {
      this.sessionStopReasons.set(
        localSessionId,
        asString(part.reason) ?? "completed",
      );
      return;
    }
  }
}
