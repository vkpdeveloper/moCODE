import { randomUUID } from "node:crypto";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";

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
import { sanitizeLogValue } from "./logger";
import {
  buildSessionDiffEntry,
  parseUnifiedDiff,
} from "./session-derived-state";
import type { JsonObject, JsonValue, ProjectRecord, SessionRecord } from "./types";

type JsonRpcRequest = {
  jsonrpc: "2.0";
  id: number;
  method: string;
  params?: Record<string, unknown>;
};

type JsonRpcResponse = {
  id: number;
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
};

type JsonRpcNotification = {
  method: string;
  params?: Record<string, unknown>;
  id?: number;
};

type PendingRpc = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
};

type PendingTurn = {
  localSessionId: string;
  resolve: (value: { stopReason: string }) => void;
  reject: (error: Error) => void;
};

type ItemTextState = {
  role: "assistant" | "reasoning";
  text: string;
};

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

function buildTextContent(text: string): JsonObject {
  return {
    type: "text",
    text,
  };
}

function stringifyUnknown(value: unknown) {
  if (value === undefined || value === null) {
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

function normalizeItemStatus(status: string | null) {
  switch (status) {
    case "completed":
      return "completed";
    case "failed":
    case "error":
      return "failed";
    case "inProgress":
    case "in_progress":
      return "in_progress";
    case "interrupted":
      return "failed";
    default:
      return "pending";
  }
}

function createSandboxPolicy(cwd: string, sandboxId: string | null) {
  switch (sandboxId) {
    case "read-only":
      return {
        type: "readOnly",
        access: {
          type: "fullAccess",
        },
        networkAccess: false,
      };
    case "danger-full-access":
      return {
        type: "dangerFullAccess",
      };
    case "workspace-write":
    default:
      return {
        type: "workspaceWrite",
        writableRoots: [cwd],
        readOnlyAccess: {
          type: "fullAccess",
        },
        networkAccess: false,
        excludeTmpdirEnvVar: false,
        excludeSlashTmp: false,
      };
  }
}

function parseModelId(value: string | null) {
  return value ? value : null;
}

function buildPlanPayload(input: {
  explanation?: string | null;
  plan?: unknown[];
  text?: string | null;
}) {
  const entries =
    input.plan && input.plan.length > 0
      ? input.plan
          .map((step) => asObject(step))
          .filter((step): step is Record<string, unknown> => step !== null)
          .map((step) => ({
            content: asString(step.step) ?? "",
            status: asString(step.status) ?? "pending",
          }))
      : (input.text ?? "")
          .split(/\n+/)
          .map((line) => line.trim())
          .filter(Boolean)
          .map((line) => ({
            content: line.replace(/^[\-\*\d\.\[\]x>\s]+/, "").trim(),
            status: "pending",
          }));

  return {
    kind: "plan",
    update: {
      explanation: input.explanation ?? null,
      entries,
    },
  } satisfies JsonObject;
}

function buildQuestionRequest(params: Record<string, unknown>): JsonObject {
  const questions = asArray(params.questions)
    .map((entry) => asObject(entry))
    .filter((entry): entry is Record<string, unknown> => entry !== null)
    .map((question, index) => ({
      id: asString(question.id) ?? `question-${index + 1}`,
      header: asString(question.header) ?? `Question ${index + 1}`,
      question: asString(question.question) ?? "",
      custom: question.isOther === true,
      secret: question.isSecret === true,
      multiple: false,
      options: asArray(question.options)
        .map((option) => asObject(option))
        .filter((option): option is Record<string, unknown> => option !== null)
        .map((option) => ({
          label: asString(option.label) ?? "",
          description: asString(option.description) ?? "",
        })),
    }));

  return {
    questions: toStoredJson(questions),
    tool: {
      messageID: `assistant:${asString(params.threadId) ?? "session"}`,
      callID: asString(params.itemId) ?? randomUUID(),
    },
  };
}

function buildQuestionResponse(
  questions: unknown[],
  answers: Record<string, string[]> | null,
) {
  if (!answers) {
    return {
      answers: {},
    };
  }

  const mapped = Object.fromEntries(
    questions
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null)
      .map((question) => asString(question.id))
      .filter((questionId): questionId is string => Boolean(questionId))
      .map((questionId) => [
        questionId,
        {
          answers: answers[questionId] ?? [],
        },
      ]),
  );

  return {
    answers: mapped,
  };
}

export class CodexRuntime extends NativeRuntimeBase {
  private child: ChildProcessWithoutNullStreams | null = null;
  private started = false;
  private startPromise: Promise<void> | null = null;
  private requestId = 1;
  private readonly pendingRpc = new Map<number, PendingRpc>();
  private readonly pendingTurns = new Map<string, PendingTurn>();
  private readonly activeTurnsBySession = new Map<string, string>();
  private readonly itemTextState = new Map<string, ItemTextState>();
  private readonly seenToolItems = new Set<string>();
  private modelCache: Array<Record<string, unknown>> = [];

  listAuthMethods(): acp.AuthMethod[] {
    return [];
  }

  getCapabilities(): acp.AgentCapabilities | null {
    return {
      loadSession: true,
      promptCapabilities: {
        image: true,
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
    if (this.started) {
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
      stdio: ["pipe", "pipe", "pipe"],
      cwd: process.cwd(),
      env: {
        ...process.env,
        ...launch.env,
      },
    });

    const rl = createInterface({ input: child.stdout });
    rl.on("line", (line) => {
      if (!line.trim()) {
        return;
      }
      try {
        this.handleMessage(JSON.parse(line) as JsonRpcResponse | JsonRpcNotification);
      } catch (error) {
        this.logger.warn("failed to parse Codex line", {
          line,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    });

    child.stderr.on("data", (chunk) => {
      const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      this.logger.warn("Codex stderr", {
        stderr: text,
      });
    });

    child.on("exit", (code, signal) => {
      this.logger.warn("Codex app-server exited", {
        code,
        signal,
      });
      this.started = false;
      this.child = null;
      for (const pending of this.pendingRpc.values()) {
        pending.reject(new Error("Codex app-server connection closed."));
      }
      this.pendingRpc.clear();
      for (const pending of this.pendingTurns.values()) {
        pending.reject(new Error("Codex app-server connection closed."));
      }
      this.pendingTurns.clear();
    });

    this.child = child;

    await this.rpc("initialize", {
      protocolVersion: 2,
      clientInfo: {
        name: "mocode-cli",
        version: "0.1.0",
      },
    });
    this.started = true;
  }

  private send(message: JsonRpcRequest | JsonRpcResponse) {
    if (!this.child?.stdin.writable) {
      throw new Error("Codex app-server is not writable.");
    }
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  private rpc<T = unknown>(method: string, params?: Record<string, unknown>) {
    const id = this.requestId++;
    const request = {
      jsonrpc: "2.0",
      id,
      method,
      ...(params === undefined ? {} : { params }),
    } satisfies JsonRpcRequest;

    return new Promise<T>((resolve, reject) => {
      this.pendingRpc.set(id, {
        resolve: resolve as (value: unknown) => void,
        reject,
      });
      try {
        this.send(request);
      } catch (error) {
        this.pendingRpc.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  private handleMessage(message: JsonRpcResponse | JsonRpcNotification) {
    if ("id" in message && message.id !== undefined && ("result" in message || "error" in message) && !("method" in message)) {
      const pending = this.pendingRpc.get(message.id);
      if (!pending) {
        return;
      }
      this.pendingRpc.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (!("method" in message) || typeof message.method !== "string") {
      return;
    }

    if ("id" in message && typeof message.id === "number") {
      void this.handleServerRequest(message.method, asObject(message.params) ?? {}, message.id);
      return;
    }

    this.handleNotification(message.method, asObject(message.params) ?? {});
  }

  private async handleServerRequest(
    method: string,
    params: Record<string, unknown>,
    id: number,
  ) {
    try {
      if (method === "item/commandExecution/requestApproval") {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        if (!localSessionId) {
          this.send({
            id,
            result: {
              decision: "cancel",
            },
          });
          return;
        }

        this.emitPermissionRequest(
          localSessionId,
          {
              toolCall: {
                toolCallId:
                  asString(params.approvalId) ??
                  asString(params.itemId) ??
                  randomUUID(),
                kind: "command_execution",
                title: "Run command",
                rawInput: toStoredJson({
                  command: asString(params.command),
                  cwd: asString(params.cwd),
                  reason: asString(params.reason),
                  commandActions: toStoredJson(params.commandActions ?? []),
                }),
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
          },
          async (outcome) => {
            const decision =
              outcome.outcome !== "selected"
                ? "cancel"
                : outcome.optionId === "allow_always"
                  ? "acceptForSession"
                  : outcome.optionId === "allow_once"
                    ? "accept"
                    : "decline";
            this.send({
              id,
              result: {
                decision,
              },
            });
          },
        );
        return;
      }

      if (method === "item/fileChange/requestApproval") {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        if (!localSessionId) {
          this.send({
            id,
            result: {
              decision: "cancel",
            },
          });
          return;
        }

        this.emitPermissionRequest(
          localSessionId,
          {
              toolCall: {
                toolCallId: asString(params.itemId) ?? randomUUID(),
                kind: "file_change",
                title: "Apply file changes",
                rawInput: toStoredJson({
                  reason: asString(params.reason),
                  grantRoot: asString(params.grantRoot),
                }),
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
          },
          async (outcome) => {
            const decision =
              outcome.outcome !== "selected"
                ? "cancel"
                : outcome.optionId === "allow_always"
                  ? "acceptForSession"
                  : outcome.optionId === "allow_once"
                    ? "accept"
                    : "decline";
            this.send({
              id,
              result: {
                decision,
              },
            });
          },
        );
        return;
      }

      if (method === "item/permissions/requestApproval") {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const requestedPermissions = asObject(params.permissions) ?? {};
        if (!localSessionId) {
          this.send({
            id,
            result: {
              permissions: {},
            },
          });
          return;
        }

        this.emitPermissionRequest(
          localSessionId,
          {
              toolCall: {
                toolCallId: asString(params.itemId) ?? randomUUID(),
                kind: "permissions",
                title: "Grant extra permissions",
                rawInput: toStoredJson(requestedPermissions),
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
          },
          async (outcome) => {
            this.send({
              id,
              result: {
                permissions:
                  outcome.outcome === "selected" &&
                  outcome.optionId !== "reject_once"
                    ? requestedPermissions
                    : {},
              },
            });
          },
        );
        return;
      }

      if (method === "item/tool/requestUserInput") {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        if (!localSessionId) {
          this.send({
            id,
            result: {
              answers: {},
            },
          });
          return;
        }

        const request = buildQuestionRequest(params);
        this.emitQuestionRequest(localSessionId, request, async (answers) => {
          this.send({
            id,
            result: buildQuestionResponse(asArray(params.questions), answers),
          });
        });
        return;
      }

      this.logger.warn("Unhandled Codex server request", {
        method,
        params: sanitizeLogValue(params),
      });
      this.send({
        id,
        result: {},
      });
    } catch (error) {
      this.send({
        id,
        error: {
          code: -32000,
          message: error instanceof Error ? error.message : String(error),
        },
      } as JsonRpcResponse);
    }
  }

  private handleNotification(method: string, params: Record<string, unknown>) {
    switch (method) {
      case "thread/status/changed": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        if (!localSessionId) {
          return;
        }
        const type = asString(asObject(params.status)?.type);
        this.db.updateSession(localSessionId, {
          status: type === "idle" ? "idle" : "running",
        });
        return;
      }
      case "thread/name/updated": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const name = asString(params.name);
        if (!localSessionId || !name) {
          return;
        }
        this.db.updateSession(localSessionId, { title: name });
        this.emitSessionEntry(localSessionId, "session_info_update", {
          kind: "session_info_update",
          update: {
            sessionUpdate: "session_info_update",
            title: name,
          },
        });
        return;
      }
      case "turn/started": {
        const threadId = asString(params.threadId) ?? "";
        const localSessionId = this.ensureBoundLocalSession(threadId);
        const turnId = asString(asObject(params.turn)?.id);
        if (!localSessionId || !turnId) {
          return;
        }
        this.activeTurnsBySession.set(localSessionId, turnId);
        return;
      }
      case "turn/completed": {
        const turn = asObject(params.turn);
        const turnId = asString(turn?.id);
        const stopReason = asString(turn?.status) ?? "completed";
        if (!turnId) {
          return;
        }
        const pending = this.pendingTurns.get(turnId);
        if (!pending) {
          return;
        }
        this.pendingTurns.delete(turnId);
        this.activeTurnsBySession.delete(pending.localSessionId);
        pending.resolve({ stopReason });
        return;
      }
      case "turn/plan/updated": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        if (!localSessionId) {
          return;
        }
        this.emitSessionEntry(localSessionId, "plan", buildPlanPayload({
          explanation: asString(params.explanation),
          plan: asArray(params.plan),
        }));
        return;
      }
      case "turn/diff/updated": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const diff = asString(params.diff) ?? "";
        if (!localSessionId) {
          return;
        }
        this.emitSessionEntry(
          localSessionId,
          "session_diff_update",
          buildSessionDiffEntry(parseUnifiedDiff(diff), diff),
        );
        return;
      }
      case "item/agentMessage/delta": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const itemId = asString(params.itemId);
        const delta = asString(params.delta);
        if (!localSessionId || !itemId || !delta) {
          return;
        }
        const state = this.itemTextState.get(itemId) ?? {
          role: "assistant",
          text: "",
        };
        state.text += delta;
        this.itemTextState.set(itemId, state);
        this.emitSessionEntry(localSessionId, "agent_message_chunk", {
          kind: "agent_message_chunk",
          content: buildTextContent(delta),
        });
        return;
      }
      case "item/reasoning/textDelta":
      case "item/reasoning/summaryTextDelta": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const itemId = asString(params.itemId);
        const delta = asString(params.delta);
        if (!localSessionId || !itemId || !delta) {
          return;
        }
        const state = this.itemTextState.get(itemId) ?? {
          role: "reasoning",
          text: "",
        };
        state.text += delta;
        this.itemTextState.set(itemId, state);
        this.emitSessionEntry(localSessionId, "agent_thought_chunk", {
          kind: "agent_thought_chunk",
          content: buildTextContent(delta),
        });
        return;
      }
      case "item/started":
      case "item/completed": {
        const localSessionId = this.ensureBoundLocalSession(
          asString(params.threadId) ?? "",
        );
        const item = asObject(params.item);
        if (!localSessionId || !item) {
          return;
        }
        this.ingestItem(localSessionId, item, method === "item/completed");
        return;
      }
      default:
        return;
    }
  }

  private ensureBoundLocalSession(threadId: string) {
    if (!threadId) {
      return null;
    }
    const binding = this.bindingsByAgentSession.get(threadId);
    if (binding) {
      return binding.localSessionId;
    }
    const session = this.db.getSessionByAgentSessionForAgent(this.agentId, threadId);
    if (!session) {
      return null;
    }
    this.bindSession(session.id, threadId, true);
    return session.id;
  }

  private async fetchModelCache() {
    if (this.modelCache.length > 0) {
      return this.modelCache;
    }
    const response = asObject(await this.rpc("model/list", {}));
    this.modelCache = asArray(response?.data)
      .map((entry) => asObject(entry))
      .filter((entry): entry is Record<string, unknown> => entry !== null);
    return this.modelCache;
  }

  private async buildCapabilities(currentModelId: string): Promise<StoredSessionCapabilities> {
    const models = await this.fetchModelCache();
    const availableModels = models.map((model) => ({
      modelId: asString(model.id) ?? "",
      name: asString(model.displayName) ?? asString(model.id) ?? "Model",
      description: asString(model.description),
    })).filter((model) => model.modelId.length > 0);

    const configOptions = [
      buildSelectConfigOption({
        id: "model",
        name: "Model",
        category: "model",
        currentValue: currentModelId,
        choices: availableModels.map((model) => ({
          value: model.modelId,
          name: model.name,
          description: model.description,
        })),
      }),
      buildSelectConfigOption({
        id: "approval_policy",
        name: "Approval Policy",
        currentValue: "on-request",
        choices: [
          { value: "on-request", name: "On Request" },
          { value: "on-failure", name: "On Failure" },
          { value: "untrusted", name: "Untrusted" },
          { value: "never", name: "Never" },
        ],
      }),
      buildSelectConfigOption({
        id: "sandbox",
        name: "Sandbox",
        currentValue: "workspace-write",
        choices: [
          { value: "workspace-write", name: "Workspace Write" },
          { value: "read-only", name: "Read Only" },
          { value: "danger-full-access", name: "Danger Full Access" },
        ],
      }),
      buildSelectConfigOption({
        id: "personality",
        name: "Personality",
        currentValue: "pragmatic",
        choices: [
          { value: "pragmatic", name: "Pragmatic" },
          { value: "friendly", name: "Friendly" },
          { value: "none", name: "None" },
        ],
      }),
    ];

    return {
      authMethods: [],
      agentCapabilities: this.getCapabilities(),
      availableCommands: [],
      models: {
        availableModels,
        currentModelId,
      },
      modes: buildModeState(
        [
          { id: "build", name: "Build" },
          { id: "plan", name: "Plan" },
        ],
        "build",
      ),
      configOptions,
    };
  }

  async createSession(
    project: ProjectRecord,
    controllerDeviceId: string | null,
  ): Promise<SessionRecord> {
    await this.ensureStarted();
    const models = await this.fetchModelCache();
    const defaultModel =
      models.find((model) => model.isDefault === true) ?? models[0] ?? null;
    const modelId = asString(defaultModel?.id) ?? "gpt-5.4";
    const response = asObject(
      await this.rpc("thread/start", {
        cwd: project.rootPath,
        model: modelId,
        approvalPolicy: "on-request",
        sandbox: "workspace-write",
        experimentalRawEvents: false,
        persistExtendedHistory: false,
      }),
    );

    const thread = asObject(response?.thread);
    const threadId = asString(thread?.id);
    if (!threadId) {
      throw new Error("Codex did not return a thread ID.");
    }

    return this.createSessionRecord({
      project,
      controllerDeviceId,
      agentSessionId: threadId,
      cwd: asString(response?.cwd) ?? project.rootPath,
      title: asString(thread?.name),
      capabilities: await this.buildCapabilities(asString(response?.model) ?? modelId),
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
    const response = asObject(
      await this.rpc("thread/resume", {
        threadId: session.agentSessionId,
      }),
    );
    const thread = asObject(response?.thread);
    const turns = asArray(thread?.turns);

    this.updateStoredCapabilities(
      session.id,
      await this.buildCapabilities(asString(response?.model) ?? session.agentSessionId),
    );

    if (this.db.listSessionEntries(session.id).length === 0) {
      for (const turn of turns) {
        const items = asArray(asObject(turn)?.items);
        for (const item of items) {
          this.ingestHistoricalItem(session.id, asObject(item));
        }
      }
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
    const configOptions = capabilities.configOptions ?? [];
    const model = parseModelId(capabilities.models?.currentModelId ?? null);
    const approvalPolicy =
      asString(
        (configOptions.find((option) => option.id === "approval_policy") as acp.SessionConfigOption | undefined)?.type === "select"
          ? (configOptions.find((option) => option.id === "approval_policy") as acp.SessionConfigSelect & { type: "select" }).currentValue
          : null,
      ) ?? "on-request";
    const sandboxId =
      asString(
        (configOptions.find((option) => option.id === "sandbox") as acp.SessionConfigOption | undefined)?.type === "select"
          ? (configOptions.find((option) => option.id === "sandbox") as acp.SessionConfigSelect & { type: "select" }).currentValue
          : null,
      ) ?? "workspace-write";
    const personality =
      asString(
        (configOptions.find((option) => option.id === "personality") as acp.SessionConfigOption | undefined)?.type === "select"
          ? (configOptions.find((option) => option.id === "personality") as acp.SessionConfigSelect & { type: "select" }).currentValue
          : null,
      ) ?? "pragmatic";
    const modeId = capabilities.modes?.currentModeId === "plan" ? "plan" : "default";

    const response = asObject(
      await this.rpc("turn/start", {
        threadId: session.agentSessionId,
        input: [
          {
            type: "text",
            text: promptState.text,
            text_elements: [],
          },
        ],
        cwd: session.cwd,
        model,
        approvalPolicy,
        sandboxPolicy: createSandboxPolicy(session.cwd, sandboxId),
        personality,
        collaborationMode: {
          mode: modeId,
          settings: {
            model,
            reasoning_effort: null,
            developer_instructions: null,
          },
        },
      }),
    );

    const turnId = asString(asObject(response?.turn)?.id);
    if (!turnId) {
      throw new Error("Codex did not return a turn ID.");
    }

    const result = await new Promise<{ stopReason: string }>((resolve, reject) => {
      this.pendingTurns.set(turnId, {
        localSessionId: session.id,
        resolve,
        reject,
      });
    });

    this.db.updateSession(session.id, {
      status: "idle",
      lastStopReason: result.stopReason,
    });
    return result;
  }

  async cancelSession(session: SessionRecord): Promise<void> {
    this.clearSessionPermissions(session.id);
    this.clearSessionQuestions(session.id);
    const turnId = this.activeTurnsBySession.get(session.id);
    if (!turnId) {
      return;
    }
    await this.rpc("turn/interrupt", {
      threadId: session.agentSessionId,
      turnId,
    });
    this.db.updateSession(session.id, {
      status: "cancelling",
    });
  }

  async listSessions(cwd: string): Promise<RuntimeListSessionsResponse> {
    await this.ensureStarted();
    const sessions: acp.SessionInfo[] = [];
    let cursor: string | null = null;

    do {
      const response = asObject(
        await this.rpc("thread/list", {
          ...(cursor ? { cursor } : {}),
          limit: 100,
        }),
      );
      const data = asArray(response?.data)
        .map((entry) => asObject(entry))
        .filter((entry): entry is Record<string, unknown> => entry !== null);
      for (const thread of data) {
        if (asString(thread.cwd) !== cwd) {
          continue;
        }
        sessions.push({
          sessionId: asString(thread.id) ?? "",
          cwd,
          title: asString(thread.name) ?? asString(thread.preview),
          updatedAt:
            typeof thread.updatedAt === "number"
              ? new Date(Number(thread.updatedAt) * 1000).toISOString()
              : null,
        });
      }
      cursor = asString(response?.nextCursor);
    } while (cursor);

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

  private ingestHistoricalItem(
    localSessionId: string,
    item: Record<string, unknown> | null,
  ) {
    if (!item) {
      return;
    }
    const type = asString(item.type);
    if (!type) {
      return;
    }

    if (type === "userMessage") {
      const content = asArray(item.content)
        .map((entry) => asObject(entry))
        .filter((entry): entry is Record<string, unknown> => entry !== null)
        .map((entry) => asString(entry.text) ?? "")
        .join("\n")
        .trim();
      if (!content) {
        return;
      }
      this.db.appendSessionEntry(localSessionId, "user_message", {
        kind: "user_message",
        text: content,
        prompt: [
          {
            type: "text",
            text: content,
          },
        ],
      });
      return;
    }

    this.ingestItem(localSessionId, item, true, false);
  }

  private ingestItem(
    localSessionId: string,
    item: Record<string, unknown>,
    completed: boolean,
    broadcast = true,
  ) {
    const type = asString(item.type);
    const itemId = asString(item.id);
    if (!type || !itemId) {
      return;
    }

    const append = (kind: string, payload: JsonObject) => {
      if (broadcast) {
        this.emitSessionEntry(localSessionId, kind, payload);
      } else {
        this.db.appendSessionEntry(localSessionId, kind, payload);
      }
    };

    if (type === "agentMessage") {
      const currentText = asString(item.text) ?? "";
      const state = this.itemTextState.get(itemId) ?? {
        role: "assistant",
        text: "",
      };
      const delta = currentText.startsWith(state.text)
        ? currentText.slice(state.text.length)
        : currentText;
      state.text = currentText;
      this.itemTextState.set(itemId, state);
      if (delta) {
        append("agent_message_chunk", {
          kind: "agent_message_chunk",
          content: buildTextContent(delta),
        });
      }
      return;
    }

    if (type === "reasoning") {
      const currentText = [...asArray(item.summary), ...asArray(item.content)]
        .map((entry) => asString(entry) ?? "")
        .join("\n")
        .trim();
      const state = this.itemTextState.get(itemId) ?? {
        role: "reasoning",
        text: "",
      };
      const delta = currentText.startsWith(state.text)
        ? currentText.slice(state.text.length)
        : currentText;
      state.text = currentText;
      this.itemTextState.set(itemId, state);
      if (delta) {
        append("agent_thought_chunk", {
          kind: "agent_thought_chunk",
          content: buildTextContent(delta),
        });
      }
      return;
    }

    if (type === "plan") {
      append("plan", buildPlanPayload({ text: asString(item.text) }));
      return;
    }

    if (
      type === "commandExecution" ||
      type === "fileChange" ||
      type === "mcpToolCall" ||
      type === "dynamicToolCall" ||
      type === "webSearch" ||
      type === "collabAgentToolCall"
    ) {
      const entryKind = this.seenToolItems.has(itemId) ? "tool_call_update" : "tool_call";
      this.seenToolItems.add(itemId);
      append(entryKind, {
        kind: entryKind,
        update: {
          toolCallId: itemId,
          kind: type,
          title:
            asString(item.tool) ??
            asString(item.command) ??
            type,
          status: normalizeItemStatus(
            completed ? "completed" : asString(item.status),
          ),
          rawInput:
            type === "commandExecution"
              ? {
                  command: asString(item.command),
                  cwd: asString(item.cwd),
                }
              : toStoredJson(item.arguments ?? item.changes ?? {}),
          rawOutput:
            asString(item.aggregatedOutput) ??
            stringifyUnknown(item.result ?? item.contentItems ?? item.changes),
          metadata: toStoredJson(item),
        },
      });
    }
  }
}
