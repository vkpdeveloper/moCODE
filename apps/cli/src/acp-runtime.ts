import * as fs from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { Readable, Writable } from "node:stream";

import * as acp from "@agentclientprotocol/sdk";
import type { Logger } from "winston";

import { StateDatabase } from "./db";
import { syncAgentCatalog } from "./agents";
import { ClaudeCodeRuntime } from "./claude-code-runtime";
import { CodexRuntime } from "./codex-runtime";
import { getLogger, sanitizeLogValue, summarizeText } from "./logger";
import { OpenCodeRuntime } from "./opencode-runtime";
import { TerminalManager } from "./terminals";
import type {
  BroadcastEvent,
  JsonObject,
  JsonValue,
  ProjectRecord,
  SessionRecord,
  StatePaths,
} from "./types";

function toStoredJson(value: unknown): JsonValue {
  return JSON.parse(JSON.stringify(value ?? null)) as JsonValue;
}

type PendingPermission = {
  id: string;
  localSessionId: string;
  request: acp.RequestPermissionRequest;
  resolve: (response: acp.RequestPermissionResponse) => void;
};

type RuntimeSessionBinding = {
  localSessionId: string;
  agentSessionId: string;
  loaded: boolean;
};

type AgentLaunchMetadata = {
  args: string[];
  env: Record<string, string>;
};

type StoredSessionCapabilities = {
  agentCapabilities?: acp.AgentCapabilities | null;
  authMethods?: acp.AuthMethod[] | null;
  availableCommands?: acp.AvailableCommand[] | null;
  configOptions?: acp.SessionConfigOption[] | null;
  models?: acp.SessionModelState | null;
  modes?: acp.SessionModeState | null;
};

function extractPromptText(prompt: acp.ContentBlock[]) {
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

function parseStoredSessionCapabilities(
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

function buildStoredSessionCapabilities(
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

function getAgentLaunchMetadata(metadataJson: string | null): AgentLaunchMetadata {
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

class RuntimeClient implements acp.Client {
  constructor(
    private readonly db: StateDatabase,
    private readonly terminalManager: TerminalManager,
    private readonly pendingPermissions: Map<string, PendingPermission>,
    private readonly bindingsByAgentSession: Map<string, RuntimeSessionBinding>,
    private readonly broadcast: (sessionId: string, event: BroadcastEvent) => void,
    private readonly logger: Logger,
  ) {}

  async requestPermission(
    params: acp.RequestPermissionRequest,
  ): Promise<acp.RequestPermissionResponse> {
    const binding = this.bindingsByAgentSession.get(params.sessionId);
    if (!binding) {
      this.logger.warn("acp permission request received for unknown session", {
        agentSessionId: params.sessionId,
        request: sanitizeLogValue(params),
      });
      return { outcome: { outcome: "cancelled" } };
    }

    this.logger.info("acp permission request received", {
      localSessionId: binding.localSessionId,
      agentSessionId: params.sessionId,
      request: sanitizeLogValue(params),
    });

    const id = randomUUID();
    const pending = await new Promise<acp.RequestPermissionResponse>((resolve) => {
      const record = {
        id,
        localSessionId: binding.localSessionId,
        request: params,
        resolve,
      } satisfies PendingPermission;
      this.pendingPermissions.set(id, record);
      this.emitPermissionRequest(record);
    });

    this.logger.info("acp permission request resolved", {
      localSessionId: binding.localSessionId,
      agentSessionId: params.sessionId,
      requestId: id,
      response: sanitizeLogValue(pending),
    });
    return pending;
  }

  async sessionUpdate(params: acp.SessionNotification): Promise<void> {
    const binding = this.bindingsByAgentSession.get(params.sessionId);
    if (!binding) {
      this.logger.warn("acp session update received for unknown binding", {
        agentSessionId: params.sessionId,
        update: sanitizeLogValue(params.update),
      });
      return;
    }

    const normalized = normalizeUpdate(params.update);
    const entry = this.db.appendSessionEntry(
      binding.localSessionId,
      normalized.kind,
      normalized.payload,
    );

    if (
      params.update.sessionUpdate === "session_info_update" &&
      "title" in params.update
    ) {
      this.db.updateSession(binding.localSessionId, {
        title: params.update.title ?? null,
      });
    }

    if (
      params.update.sessionUpdate === "available_commands_update" ||
      params.update.sessionUpdate === "config_option_update" ||
      params.update.sessionUpdate === "current_mode_update"
    ) {
      const session = this.db.getSession(binding.localSessionId);
      if (session) {
        const current = parseStoredSessionCapabilities(session.capabilitiesJson);
        let next = current;

        if (params.update.sessionUpdate === "available_commands_update") {
          next = buildStoredSessionCapabilities(current, {
            availableCommands: params.update.availableCommands,
          });
        }

        if (params.update.sessionUpdate === "config_option_update") {
          next = buildStoredSessionCapabilities(current, {
            configOptions: params.update.configOptions,
          });
        }

        if (params.update.sessionUpdate === "current_mode_update") {
          next = buildStoredSessionCapabilities(current, {
            modes: {
              availableModes: current.modes?.availableModes ?? [],
              currentModeId: params.update.currentModeId,
            },
          });
        }

        this.db.updateSession(binding.localSessionId, {
          capabilities: toStoredJson(next),
        });
      }
    }

    this.logger.debug("acp session update stored", {
      localSessionId: binding.localSessionId,
      agentSessionId: params.sessionId,
      kind: normalized.kind,
      payload: sanitizeLogValue(normalized.payload),
    });

    this.broadcast(binding.localSessionId, {
      type: "session_update",
      payload: {
        sessionId: binding.localSessionId,
        entry: toStoredJson(entry) as JsonValue,
      },
    });
  }

  async writeTextFile(
    params: acp.WriteTextFileRequest,
  ): Promise<acp.WriteTextFileResponse> {
    this.logger.info("acp fs write_text_file", {
      path: params.path,
      contentPreview: summarizeText(params.content),
      contentLength: params.content.length,
    });
    await fs.writeFile(params.path, params.content, "utf8");
    return {};
  }

  async readTextFile(
    params: acp.ReadTextFileRequest,
  ): Promise<acp.ReadTextFileResponse> {
    const content = await fs.readFile(params.path, "utf8");
    this.logger.info("acp fs read_text_file", {
      path: params.path,
      contentPreview: summarizeText(content),
      contentLength: content.length,
    });
    return { content };
  }

  async createTerminal(
    params: acp.CreateTerminalRequest,
  ): Promise<acp.CreateTerminalResponse> {
    this.logger.info("acp terminal create", {
      params: sanitizeLogValue(params),
    });
    const response = await this.terminalManager.createTerminal({
      command: params.command,
      args: params.args,
      cwd: params.cwd ?? null,
      env: params.env ?? [],
      outputByteLimit: params.outputByteLimit ?? null,
    });
    this.logger.info("acp terminal created", {
      terminalId: response.terminalId,
    });
    return response;
  }

  async terminalOutput(
    params: acp.TerminalOutputRequest,
  ): Promise<acp.TerminalOutputResponse> {
    const response = await this.terminalManager.terminalOutput(params.terminalId);
    this.logger.debug("acp terminal output", {
      terminalId: params.terminalId,
      response: sanitizeLogValue(response),
    });
    return response;
  }

  async releaseTerminal(
    params: acp.ReleaseTerminalRequest,
  ): Promise<acp.ReleaseTerminalResponse> {
    this.logger.info("acp terminal release", {
      terminalId: params.terminalId,
    });
    return await this.terminalManager.releaseTerminal(params.terminalId);
  }

  async waitForTerminalExit(
    params: acp.WaitForTerminalExitRequest,
  ): Promise<acp.WaitForTerminalExitResponse> {
    const response = await this.terminalManager.waitForExit(params.terminalId);
    this.logger.info("acp terminal wait_for_exit", {
      terminalId: params.terminalId,
      response: sanitizeLogValue(response),
    });
    return response;
  }

  async killTerminal(
    params: acp.KillTerminalRequest,
  ): Promise<acp.KillTerminalResponse> {
    this.logger.warn("acp terminal kill", {
      terminalId: params.terminalId,
    });
    return await this.terminalManager.killTerminal(params.terminalId);
  }

  emitPermissionRequest(pending: PendingPermission) {
    this.logger.info("broadcasting permission request", {
      requestId: pending.id,
      localSessionId: pending.localSessionId,
      request: sanitizeLogValue(pending.request),
    });
    this.broadcast(pending.localSessionId, {
      type: "permission_request",
      payload: {
        requestId: pending.id,
        sessionId: pending.localSessionId,
        request: toStoredJson(pending.request),
      },
    });
  }
}

class AgentRuntime {
  private child: ChildProcessWithoutNullStreams | null = null;
  private connection: acp.ClientSideConnection | null = null;
  private client: RuntimeClient;
  private initialized = false;
  private readonly pendingPermissions = new Map<string, PendingPermission>();
  private readonly bindingsByAgentSession = new Map<string, RuntimeSessionBinding>();
  private readonly bindingsByLocalSession = new Map<string, RuntimeSessionBinding>();
  private agentCapabilities: acp.AgentCapabilities | null = null;
  private authMethods: acp.AuthMethod[] = [];
  private readonly logger: Logger;

  constructor(
    readonly agentId: string,
    private readonly db: StateDatabase,
    private readonly terminalManager: TerminalManager,
    private readonly paths: StatePaths,
    private readonly broadcast: (sessionId: string, event: BroadcastEvent) => void,
    parentLogger: Logger,
  ) {
    this.logger = parentLogger.child({ agentId });
    this.client = new RuntimeClient(
      this.db,
      this.terminalManager,
      this.pendingPermissions,
      this.bindingsByAgentSession,
      this.broadcast,
      this.logger.child({ component: "client" }),
    );
  }

  async ensureStarted() {
    if (this.connection && this.initialized) {
      return this.connection;
    }

    const agent = this.db.getAgent(this.agentId);
    const launch = getAgentLaunchMetadata(agent?.metadataJson ?? null);

    if (!agent?.binaryPath) {
      this.logger.error("agent runtime unavailable", {
        agentRecord: sanitizeLogValue(agent),
      });
      throw new Error(`Agent ${this.agentId} is unavailable on this machine.`);
    }

    this.logger.info("starting agent runtime", {
      binaryPath: agent.binaryPath,
      args: launch.args,
      cwd: process.cwd(),
    });
    const child = spawn(agent.binaryPath, launch.args, {
      stdio: ["pipe", "pipe", "pipe"],
      cwd: process.cwd(),
      env: {
        ...process.env,
        ...launch.env,
      },
    });

    child.stderr.on("data", (chunk) => {
      const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      this.logger.warn("agent stderr", {
        stderr: summarizeText(text, 400),
      });
    });

    child.on("exit", (code, signal) => {
      this.logger.warn("agent process exited", {
        code,
        signal,
      });
      this.child = null;
      this.connection = null;
      this.initialized = false;
    });

    const input = Writable.toWeb(child.stdin) as WritableStream<Uint8Array>;
    const output =
      Readable.toWeb(child.stdout) as unknown as ReadableStream<Uint8Array>;
    const stream = acp.ndJsonStream(input, output);
    const connection = new acp.ClientSideConnection(() => this.client, stream);

    this.logger.info("acp initialize request", {
      protocolVersion: acp.PROTOCOL_VERSION,
      clientInfo: {
        name: "mocode-cli",
        title: "moCODE CLI",
        version: "0.1.0",
      },
    });
    const result = await connection.initialize({
      protocolVersion: acp.PROTOCOL_VERSION,
      clientInfo: {
        name: "mocode-cli",
        title: "moCODE CLI",
        version: "0.1.0",
      },
      clientCapabilities: {
        fs: {
          readTextFile: true,
          writeTextFile: true,
        },
        terminal: true,
      },
    });

    this.child = child;
    this.connection = connection;
    this.initialized = true;
    this.agentCapabilities = result.agentCapabilities ?? null;
    this.authMethods = result.authMethods ?? [];

    this.logger.info("acp initialize response", {
      authMethods: sanitizeLogValue(this.authMethods),
      capabilities: sanitizeLogValue(this.agentCapabilities),
    });

    return connection;
  }

  listAuthMethods() {
    return this.authMethods;
  }

  getCapabilities() {
    return this.agentCapabilities;
  }

  supportsSessionListing() {
    return Boolean(this.agentCapabilities?.sessionCapabilities?.list);
  }

  private updateStoredCapabilities(
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

  async authenticate(params: acp.AuthenticateRequest) {
    const connection = await this.ensureStarted();
    this.logger.info("acp authenticate request", {
      params: sanitizeLogValue(params),
    });
    const response = await connection.authenticate(params);
    this.logger.info("acp authenticate response", {
      response: sanitizeLogValue(response),
    });
    return response;
  }

  async createSession(project: ProjectRecord, controllerDeviceId: string | null) {
    const connection = await this.ensureStarted();
    this.logger.info("acp new_session request", {
      projectId: project.id,
      rootPath: project.rootPath,
      controllerDeviceId,
    });
    const response = await connection.newSession({
      cwd: project.rootPath,
      mcpServers: [],
    });
    this.logger.info("acp new_session response", {
      agentSessionId: response.sessionId,
      modes: sanitizeLogValue(response.modes),
      configOptions: sanitizeLogValue(response.configOptions),
    });

    const session = this.db.createSession({
      projectId: project.id,
      agentId: this.agentId,
      agentSessionId: response.sessionId,
      cwd: project.rootPath,
      title: null,
      status: "idle",
      controllerDeviceId,
      capabilities: toStoredJson({
        authMethods: this.authMethods,
        agentCapabilities: this.agentCapabilities,
        availableCommands: [],
        models: response.models ?? null,
        modes: response.modes ?? null,
        configOptions: response.configOptions ?? null,
      }),
    });

    const binding = {
      localSessionId: session.id,
      agentSessionId: response.sessionId,
      loaded: true,
    };
    this.bindingsByAgentSession.set(response.sessionId, binding);
    this.bindingsByLocalSession.set(session.id, binding);

    this.logger.info("local session created", {
      localSessionId: session.id,
      agentSessionId: response.sessionId,
      projectId: project.id,
    });

    return session;
  }

  async ensureSessionLoaded(session: SessionRecord) {
    await this.ensureStarted();
    const existing = this.bindingsByLocalSession.get(session.id);
    if (existing?.loaded) {
      this.logger.debug("session already loaded", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
      });
      return existing;
    }

    if (!this.connection) {
      throw new Error("Agent runtime is not connected.");
    }

    const binding = existing ?? {
      localSessionId: session.id,
      agentSessionId: session.agentSessionId,
      loaded: false,
    };

    this.bindingsByAgentSession.set(session.agentSessionId, binding);
    this.bindingsByLocalSession.set(session.id, binding);

    if (this.agentCapabilities?.loadSession) {
      this.logger.info("acp load_session request", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
        cwd: session.cwd,
      });
      const response = await this.connection.loadSession({
        sessionId: session.agentSessionId,
        cwd: session.cwd,
        mcpServers: [],
      });
      this.updateStoredCapabilities(session.id, {
        authMethods: this.authMethods,
        agentCapabilities: this.agentCapabilities,
        models: response.models ?? null,
        modes: response.modes ?? null,
        configOptions: response.configOptions ?? null,
      });
      this.logger.info("acp load_session response", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
      });
    } else {
      this.logger.debug("agent does not support load_session", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
      });
    }

    binding.loaded = true;
    return binding;
  }

  async promptSession(session: SessionRecord, prompt: acp.ContentBlock[]) {
    if (!this.connection) {
      await this.ensureStarted();
    }
    if (!this.connection) {
      throw new Error("Agent runtime is unavailable.");
    }

    await this.ensureSessionLoaded(session);
    this.db.updateSession(session.id, { status: "running" });
    const promptText = extractPromptText(prompt);
    const entry = this.db.appendSessionEntry(session.id, "user_message", {
      kind: "user_message",
      prompt: toStoredJson(prompt),
      text: promptText,
    });
    this.logger.info("acp prompt request", {
      localSessionId: session.id,
      agentSessionId: session.agentSessionId,
      prompt: summarizeText(promptText, 240),
    });
    this.broadcast(session.id, {
      type: "session_update",
      payload: {
        sessionId: session.id,
        entry: toStoredJson(entry) as JsonValue,
      },
    });

    const response = await this.connection.prompt({
      sessionId: session.agentSessionId,
      prompt,
    });
    this.logger.info("acp prompt response", {
      localSessionId: session.id,
      agentSessionId: session.agentSessionId,
      stopReason: response.stopReason,
      metadata: sanitizeLogValue(response),
    });

    this.db.updateSession(session.id, {
      status: "idle",
      lastStopReason: response.stopReason,
    });

    return response;
  }

  async cancelSession(session: SessionRecord) {
    if (!this.connection) {
      this.logger.warn("cancel requested without active connection", {
        localSessionId: session.id,
        agentSessionId: session.agentSessionId,
      });
      return;
    }

    for (const [id, pending] of this.pendingPermissions.entries()) {
      if (pending.localSessionId !== session.id) {
        continue;
      }
      this.pendingPermissions.delete(id);
      pending.resolve({ outcome: { outcome: "cancelled" } });
    }

    this.logger.warn("acp cancel request", {
      localSessionId: session.id,
      agentSessionId: session.agentSessionId,
    });
    await this.connection.cancel({
      sessionId: session.agentSessionId,
    });

    this.db.updateSession(session.id, { status: "cancelling" });
  }

  async listSessions(cwd: string) {
    const connection = await this.ensureStarted();
    const response = await connection.listSessions({
      cwd,
    });
    this.logger.info("acp list_sessions response", {
      agentId: this.agentId,
      cwd,
      sessionCount: response.sessions.length,
      nextCursor: response.nextCursor ?? null,
    });
    return response;
  }

  async setSessionMode(session: SessionRecord, modeId: string) {
    const connection = await this.ensureStarted();
    await this.ensureSessionLoaded(session);
    await connection.setSessionMode({
      sessionId: session.agentSessionId,
      modeId,
    });

    const current = parseStoredSessionCapabilities(session.capabilitiesJson);
    this.updateStoredCapabilities(session.id, {
      modes: {
        availableModes: current.modes?.availableModes ?? [],
        currentModeId: modeId,
      },
    });
  }

  async setSessionConfigOption(
    session: SessionRecord,
    request:
      | {
          configId: string;
          type: "boolean";
          value: boolean;
        }
      | {
          type: "value";
          configId: string;
          value: string;
        },
  ) {
    const connection = await this.ensureStarted();
    await this.ensureSessionLoaded(session);
    const response = await connection.setSessionConfigOption({
      sessionId: session.agentSessionId,
      configId: request.configId,
      ...(request.type === "boolean"
        ? {
            type: "boolean" as const,
            value: request.value,
          }
        : {
            type: "value" as const,
            value: request.value,
          }),
    });
    this.updateStoredCapabilities(session.id, {
      configOptions: response.configOptions,
    });
    return response;
  }

  replyPermission(
    requestId: string,
    outcome: acp.RequestPermissionOutcome,
  ): boolean {
    const pending = this.pendingPermissions.get(requestId);
    if (!pending) {
      this.logger.warn("permission reply requested for unknown request", {
        requestId,
        outcome: sanitizeLogValue(outcome),
      });
      return false;
    }
    this.logger.info("permission reply resolved", {
      requestId,
      localSessionId: pending.localSessionId,
      outcome: sanitizeLogValue(outcome),
    });
    this.pendingPermissions.delete(requestId);
    pending.resolve({ outcome });
    return true;
  }

  replyQuestion(
    _requestId: string,
    _answers: Record<string, string[]> | null,
  ): boolean {
    return false;
  }

  flushPendingPermissionNotifications() {
    for (const pending of this.pendingPermissions.values()) {
      this.client.emitPermissionRequest(pending);
    }
  }
}

function normalizeUpdate(update: acp.SessionUpdate): {
  kind: string;
  payload: JsonObject;
} {
  switch (update.sessionUpdate) {
    case "user_message_chunk":
    case "agent_message_chunk":
    case "agent_thought_chunk":
      return {
        kind: update.sessionUpdate,
        payload: {
          kind: update.sessionUpdate,
          content: toStoredJson(update.content),
        },
      };
    case "tool_call":
    case "tool_call_update":
    case "plan":
    case "available_commands_update":
    case "current_mode_update":
    case "config_option_update":
    case "session_info_update":
      return {
        kind: update.sessionUpdate,
        payload: {
          kind: update.sessionUpdate,
          update: toStoredJson(update),
        },
      };
    default:
      return {
        kind: "unknown_update",
        payload: {
          kind: "unknown_update",
          update: toStoredJson(update),
        },
      };
  }
}

export class AgentRuntimeManager {
  private readonly terminalManager = new TerminalManager();
  private readonly runtimes = new Map<
    string,
    AgentRuntime | OpenCodeRuntime | CodexRuntime | ClaudeCodeRuntime
  >();
  private readonly logger: Logger;

  constructor(
    private readonly db: StateDatabase,
    private readonly paths: StatePaths,
    private readonly broadcast: (sessionId: string, event: BroadcastEvent) => void,
    parentLogger: Logger = getLogger("acp-runtime"),
  ) {
    this.logger = parentLogger.child({ component: "manager" });
  }

  listAgents() {
    const descriptors = syncAgentCatalog(this.db, this.paths).map((descriptor) => ({
      ...descriptor,
      authMethods: this.getRuntimeIfStarted(descriptor.id)?.listAuthMethods() ?? [],
      capabilities:
        this.getRuntimeIfStarted(descriptor.id)?.getCapabilities() ?? null,
    }));
    this.logger.debug("listed agents", {
      agents: sanitizeLogValue(descriptors),
    });
    return descriptors;
  }

  private getRuntime(agentId: string) {
    const existing = this.runtimes.get(agentId);
    if (existing) {
      return existing;
    }

    const descriptor =
      this.db.getAgent(agentId) ??
      syncAgentCatalog(this.db, this.paths).find((entry) => entry.id === agentId) ??
      null;

    const runtime =
      descriptor?.source === "opencode-server"
        ? new OpenCodeRuntime(
            agentId,
            this.db,
            this.paths,
            this.broadcast,
            this.logger,
          )
        : descriptor?.source === "codex-app-server"
          ? new CodexRuntime(
              agentId,
              this.db,
              this.paths,
              this.broadcast,
              this.logger,
            )
          : descriptor?.source === "claude-code"
            ? new ClaudeCodeRuntime(
                agentId,
                this.db,
                this.paths,
                this.broadcast,
                this.logger,
              )
            : new AgentRuntime(
                agentId,
                this.db,
                this.terminalManager,
                this.paths,
                this.broadcast,
                this.logger,
              );
    this.runtimes.set(agentId, runtime);
    return runtime;
  }

  private getRuntimeIfStarted(agentId: string) {
    return this.runtimes.get(agentId) ?? null;
  }

  async initializeAgent(agentId: string) {
    this.logger.info("initialize agent requested", { agentId });
    const runtime = this.getRuntime(agentId);
    await runtime.ensureStarted();
    return {
      authMethods: runtime.listAuthMethods(),
      capabilities: runtime.getCapabilities(),
    };
  }

  async authenticateAgent(agentId: string, params: acp.AuthenticateRequest) {
    this.logger.info("authenticate agent requested", {
      agentId,
      params: sanitizeLogValue(params),
    });
    const runtime = this.getRuntime(agentId);
    await runtime.ensureStarted();
    return await runtime.authenticate(params);
  }

  async createSession(
    project: ProjectRecord,
    agentId: string,
    controllerDeviceId: string | null,
  ) {
    this.logger.info("create session requested", {
      projectId: project.id,
      agentId,
      controllerDeviceId,
    });
    const runtime = this.getRuntime(agentId);
    const session = await runtime.createSession(project, controllerDeviceId);
    return this.db.getSessionSnapshot(session.id);
  }

  async listSessionsForAgent(
    project: ProjectRecord,
    agentId: string,
  ): Promise<SessionRecord[]> {
    try {
      const runtime = this.getRuntime(agentId);
      await runtime.ensureStarted();
      if (!runtime.supportsSessionListing()) {
        return this.db
          .listSessions(project.id)
          .filter((session) => session.agentId === agentId);
      }

      const response = await runtime.listSessions(project.rootPath);
      const baseCapabilities = {
        authMethods: runtime.listAuthMethods(),
        agentCapabilities: runtime.getCapabilities(),
      } satisfies StoredSessionCapabilities;

      for (const info of response.sessions) {
        this.db.upsertSessionFromAgent({
          projectId: project.id,
          agentId,
          agentSessionId: info.sessionId,
          cwd: info.cwd,
          title: info.title ?? null,
          status: "idle",
          capabilities: toStoredJson(baseCapabilities),
        });
      }

      return this.db
        .listSessions(project.id)
        .filter((session) => session.agentId === agentId);
    }
    catch (error) {
      this.logger.warn("list sessions via agent failed; falling back to local db", {
        projectId: project.id,
        agentId,
        error: sanitizeLogValue(error),
      });
    }
    return this.db
      .listSessions(project.id)
      .filter((session) => session.agentId === agentId);
  }

  async loadSession(localSessionId: string) {
    this.logger.info("load session requested", {
      localSessionId,
    });
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }

    const runtime = this.getRuntime(session.agentId);
    await runtime.ensureSessionLoaded(session);
    return this.db.getSessionSnapshot(localSessionId);
  }

  async promptSession(localSessionId: string, prompt: acp.ContentBlock[]) {
    const promptText = extractPromptText(prompt);
    this.logger.info("prompt session requested", {
      localSessionId,
      prompt: summarizeText(promptText, 240),
    });
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const runtime = this.getRuntime(session.agentId);
    const response = await runtime.promptSession(session, prompt);
    return {
      session: this.db.getSession(localSessionId),
      response,
    };
  }

  async cancelSession(localSessionId: string) {
    this.logger.warn("cancel session requested", {
      localSessionId,
    });
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const runtime = this.getRuntime(session.agentId);
    await runtime.cancelSession(session);
  }

  getSessionState(localSessionId: string) {
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const capabilities = parseStoredSessionCapabilities(session.capabilitiesJson);
    return {
      session,
      availableCommands: capabilities.availableCommands ?? [],
      configOptions: capabilities.configOptions ?? [],
      modes: capabilities.modes ?? null,
      models: capabilities.models ?? null,
    };
  }

  async setSessionMode(localSessionId: string, modeId: string) {
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const runtime = this.getRuntime(session.agentId);
    await runtime.setSessionMode(session, modeId);
    return this.getSessionState(localSessionId);
  }

  async setSessionConfigOption(
    localSessionId: string,
    request:
      | {
          configId: string;
          type: "boolean";
          value: boolean;
        }
      | {
          type: "value";
          configId: string;
          value: string;
        },
  ) {
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const runtime = this.getRuntime(session.agentId);
    await runtime.setSessionConfigOption(session, request);
    return this.getSessionState(localSessionId);
  }

  replyPermission(
    sessionId: string,
    requestId: string,
    outcome: acp.RequestPermissionOutcome,
  ) {
    const session = this.db.getSession(sessionId);
    if (!session) {
      this.logger.warn("permission reply requested for unknown session", {
        sessionId,
        requestId,
        outcome: sanitizeLogValue(outcome),
      });
      return false;
    }
    const runtime = this.getRuntime(session.agentId);
    return runtime.replyPermission(requestId, outcome);
  }

  replyQuestion(
    sessionId: string,
    requestId: string,
    answers: Record<string, string[]> | null,
  ) {
    const session = this.db.getSession(sessionId);
    if (!session) {
      this.logger.warn("question reply requested for unknown session", {
        sessionId,
        requestId,
        answers: sanitizeLogValue(answers),
      });
      return false;
    }
    const runtime = this.getRuntime(session.agentId);
    return runtime.replyQuestion(requestId, answers);
  }
}
