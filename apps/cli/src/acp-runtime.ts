import * as fs from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { Readable, Writable } from "node:stream";

import * as acp from "@agentclientprotocol/sdk";
import type { Logger } from "winston";

import { StateDatabase } from "./db";
import { syncAgentCatalog } from "./agents";
import { getLogger, sanitizeLogValue, summarizeText } from "./logger";
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
      await this.connection.loadSession({
        sessionId: session.agentSessionId,
        cwd: session.cwd,
        mcpServers: [],
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

  async promptSession(session: SessionRecord, text: string) {
    if (!this.connection) {
      await this.ensureStarted();
    }
    if (!this.connection) {
      throw new Error("Agent runtime is unavailable.");
    }

    await this.ensureSessionLoaded(session);
    this.db.updateSession(session.id, { status: "running" });
    const entry = this.db.appendSessionEntry(session.id, "user_message", {
      kind: "user_message",
      text,
    });
    this.logger.info("acp prompt request", {
      localSessionId: session.id,
      agentSessionId: session.agentSessionId,
      prompt: summarizeText(text, 240),
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
      prompt: [{ type: "text", text }],
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
  private readonly runtimes = new Map<string, AgentRuntime>();
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
    const runtime = new AgentRuntime(
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

  async promptSession(localSessionId: string, text: string) {
    this.logger.info("prompt session requested", {
      localSessionId,
      prompt: summarizeText(text, 240),
    });
    const session = this.db.getSession(localSessionId);
    if (!session) {
      throw new Error(`Unknown session ${localSessionId}`);
    }
    const runtime = this.getRuntime(session.agentId);
    const response = await runtime.promptSession(session, text);
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
}
