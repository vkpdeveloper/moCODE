import { randomUUID } from "node:crypto";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createServer, type Server } from "node:http";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";

import * as acp from "@agentclientprotocol/sdk";

import {
  NativeRuntimeBase,
  getAgentLaunchMetadata,
  type RuntimeSessionBinding,
  buildModeState,
  buildSelectConfigOption,
  parseStoredSessionCapabilities,
  toStoredJson,
  updateConfigOptions,
  type RuntimeListSessionsResponse,
  type SessionConfigRequest,
  type StoredSessionCapabilities,
} from "./native-runtime-support";
import type { JsonObject, ProjectRecord, SessionRecord } from "./types";

type ClaudeHookPayload = {
  session_id?: string;
  transcript_path?: string;
  cwd?: string;
  [key: string]: unknown;
};

type ActiveClaudePrompt = {
  child: ChildProcessWithoutNullStreams;
  alwaysAllowTools: Set<string>;
  resolve: (value: { stopReason: string }) => void;
  reject: (error: Error) => void;
};

type TextAccumulator = {
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

function transcriptDirForCwd(cwd: string) {
  return join(
    homedir(),
    ".claude",
    "projects",
    resolve(cwd).replace(/[^a-zA-Z0-9-]/g, "-"),
  );
}

function transcriptPathForSession(cwd: string, sessionId: string) {
  return join(transcriptDirForCwd(cwd), `${sessionId}.jsonl`);
}

function permissionModeForMode(modeId: string) {
  return modeId === "plan" ? "plan" : "default";
}

function modeIdForPermissionMode(permissionMode: string | null) {
  return permissionMode === "plan" ? "plan" : "build";
}

function buildClaudeCapabilities(currentModelId = "sonnet"): StoredSessionCapabilities {
  const availableModels = [
    {
      modelId: "sonnet",
      name: "Sonnet",
      description: "Claude latest Sonnet alias",
    },
    {
      modelId: "opus",
      name: "Opus",
      description: "Claude latest Opus alias",
    },
  ];

  return {
    authMethods: [],
    agentCapabilities: {
      loadSession: true,
      promptCapabilities: {
        image: false,
        audio: false,
        embeddedContext: true,
      },
      sessionCapabilities: {
        list: {},
      },
    },
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
    configOptions: [
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
    ],
  };
}

export class ClaudeCodeRuntime extends NativeRuntimeBase {
  private hookServer: Server | null = null;
  private hookPort: number | null = null;
  private hookSettingsPath: string | null = null;
  private started = false;
  private startPromise: Promise<void> | null = null;
  private readonly transcriptPaths = new Map<string, string>();
  private readonly activePrompts = new Map<string, ActiveClaudePrompt>();
  private readonly assistantText = new Map<string, TextAccumulator>();
  private readonly assistantThinking = new Map<string, TextAccumulator>();
  private readonly streamingMessageIds = new Map<string, string>();
  private readonly seenToolCalls = new Set<string>();

  listAuthMethods(): acp.AuthMethod[] {
    return [];
  }

  getCapabilities(): acp.AgentCapabilities | null {
    return buildClaudeCapabilities().agentCapabilities ?? null;
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
    this.startPromise = this.startHookServer();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = null;
    }
  }

  private async startHookServer() {
    await mkdir(join(this.paths.cacheDir, "claude-hooks"), { recursive: true });

    await new Promise<void>((resolve, reject) => {
      const server = createServer(async (request, response) => {
        if (request.method !== "POST" || request.url !== "/hook/session-start") {
          response.writeHead(404).end("not found");
          return;
        }

        try {
          const chunks: Buffer[] = [];
          for await (const chunk of request) {
            chunks.push(Buffer.from(chunk));
          }
          const body = Buffer.concat(chunks).toString("utf8");
          const payload = (JSON.parse(body) as ClaudeHookPayload) ?? {};
          this.handleHook(payload);
          response.writeHead(200, { "content-type": "text/plain" }).end("ok");
        } catch (error) {
          response.writeHead(500, { "content-type": "text/plain" }).end(
            error instanceof Error ? error.message : String(error),
          );
        }
      });

      server.listen(0, "127.0.0.1", () => {
        const address = server.address();
        if (!address || typeof address === "string") {
          reject(new Error("Unable to start Claude hook server."));
          return;
        }
        this.hookServer = server;
        this.hookPort = address.port;
        resolve();
      });
      server.on("error", reject);
    });

    const hookScript = resolve(
      dirname(new URL(import.meta.url).pathname),
      "..",
      "scripts",
      "claude_session_hook.cjs",
    );
    const settingsPath = join(
      this.paths.cacheDir,
      "claude-hooks",
      `settings-${process.pid}.json`,
    );
    await writeFile(
      settingsPath,
      `${JSON.stringify(
        {
          hooks: {
            SessionStart: [
              {
                matcher: "*",
                hooks: [
                  {
                    type: "command",
                    command: `node "${hookScript}" ${this.hookPort}`,
                  },
                ],
              },
            ],
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    this.hookSettingsPath = settingsPath;
    this.started = true;
  }

  private handleHook(payload: ClaudeHookPayload) {
    const sessionId = asString(payload.session_id);
    const transcriptPath = asString(payload.transcript_path);
    if (!sessionId || !transcriptPath) {
      return;
    }
    this.transcriptPaths.set(sessionId, transcriptPath);
  }

  async createSession(
    project: ProjectRecord,
    controllerDeviceId: string | null,
  ): Promise<SessionRecord> {
    await this.ensureStarted();
    return this.createSessionRecord({
      project,
      controllerDeviceId,
      agentSessionId: randomUUID(),
      cwd: project.rootPath,
      capabilities: buildClaudeCapabilities(),
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
    if (!session.capabilitiesJson) {
      this.updateStoredCapabilities(session.id, buildClaudeCapabilities());
    }

    if (this.db.listSessionEntries(session.id).length === 0) {
      await this.hydrateTranscript(session);
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
    const modeId = capabilities.modes?.currentModeId ?? "build";
    const permissionMode = permissionModeForMode(modeId);
    const modelId = capabilities.models?.currentModelId ?? "sonnet";
    const transcriptPath = this.transcriptPaths.get(session.agentSessionId);
    const shouldResume = Boolean(transcriptPath ?? await this.sessionTranscriptExists(session));
    const agent = this.db.getAgent(this.agentId);
    const launch = getAgentLaunchMetadata(agent?.metadataJson ?? null);

    if (!agent?.binaryPath) {
      throw new Error(`Agent ${this.agentId} is unavailable on this machine.`);
    }

    const args = [
      "-p",
      "--verbose",
      "--input-format",
      "stream-json",
      "--output-format",
      "stream-json",
      "--include-partial-messages",
      "--permission-prompt-tool",
      "stdio",
      "--permission-mode",
      permissionMode,
      "--model",
      modelId,
      "--settings",
      this.hookSettingsPath ?? "{}",
      ...(shouldResume
        ? ["--resume", session.agentSessionId]
        : ["--session-id", session.agentSessionId]),
    ];

    const child = spawn(agent.binaryPath, [...launch.args, ...args], {
      cwd: session.cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        ...launch.env,
      },
    });

    const completion = new Promise<{ stopReason: string }>((resolve, reject) => {
      this.activePrompts.set(session.id, {
        child,
        alwaysAllowTools: new Set<string>(),
        resolve,
        reject,
      });
    });

    child.stderr.on("data", (chunk) => {
      const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      this.logger.warn("Claude stderr", {
        localSessionId: session.id,
        stderr: text,
      });
    });

    const rl = createInterface({ input: child.stdout });
    rl.on("line", (line) => {
      if (!line.trim()) {
        return;
      }
      try {
        const payload = JSON.parse(line) as Record<string, unknown>;
        this.handleClaudePayload(session, payload);
      } catch (error) {
        this.logger.warn("failed to parse Claude stream event", {
          localSessionId: session.id,
          line,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    });

    child.on("close", (code) => {
      const active = this.activePrompts.get(session.id);
      if (!active) {
        return;
      }
      if (code !== 0) {
        active.reject(new Error(`Claude Code exited with code ${code ?? "unknown"}.`));
        this.activePrompts.delete(session.id);
      }
    });

    child.stdin.write(
      `${JSON.stringify({
        type: "user",
        message: {
          role: "user",
          content: promptState.text,
        },
      })}\n`,
    );
    child.stdin.end();

    try {
      const result = await completion;
      this.db.updateSession(session.id, {
        status: "idle",
        lastStopReason: result.stopReason,
      });
      return result;
    } finally {
      this.activePrompts.delete(session.id);
      this.streamingMessageIds.delete(session.id);
    }
  }

  async cancelSession(session: SessionRecord): Promise<void> {
    this.clearSessionPermissions(session.id);
    this.clearSessionQuestions(session.id);
    const active = this.activePrompts.get(session.id);
    if (!active) {
      return;
    }
    active.child.stdin.write(
      `${JSON.stringify({
        request_id: randomUUID(),
        type: "control_request",
        request: {
          subtype: "interrupt",
        },
      })}\n`,
    );
    this.db.updateSession(session.id, {
      status: "cancelling",
    });
  }

  async listSessions(cwd: string): Promise<RuntimeListSessionsResponse> {
    const directory = transcriptDirForCwd(cwd);
    let entries: Array<{ isFile(): boolean; name: string }> = [];
    try {
      entries = (await readdir(directory, {
        withFileTypes: true,
      })) as Array<{ isFile(): boolean; name: string }>;
    } catch {
      return { sessions: [] };
    }

    const sessions: acp.SessionInfo[] = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".jsonl")) {
        continue;
      }
      const sessionId = entry.name.slice(0, -".jsonl".length);
      const filePath = join(directory, entry.name);
      const title = await this.deriveTranscriptTitle(filePath);
      const fileStat = await stat(filePath);
      sessions.push({
        sessionId,
        cwd,
        title,
        updatedAt: fileStat.mtime.toISOString(),
      });
    }

    sessions.sort((left, right) => (right.updatedAt ?? "").localeCompare(left.updatedAt ?? ""));
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
            availableModels: current.models?.availableModels ?? buildClaudeCapabilities().models?.availableModels ?? [],
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

  private async sessionTranscriptExists(session: SessionRecord) {
    try {
      await stat(this.getTranscriptPath(session));
      return true;
    } catch {
      return false;
    }
  }

  private getTranscriptPath(session: SessionRecord) {
    return this.transcriptPaths.get(session.agentSessionId)
      ?? transcriptPathForSession(session.cwd, session.agentSessionId);
  }

  private async deriveTranscriptTitle(filePath: string) {
    try {
      const content = await readFile(filePath, "utf8");
      for (const rawLine of content.split(/\n/)) {
        const line = rawLine.trim();
        if (!line) {
          continue;
        }
        const entry = asObject(JSON.parse(line));
        if (asString(entry?.type) !== "user") {
          continue;
        }
        const message = asObject(entry?.message);
        const contentValue = message?.content;
        if (typeof contentValue === "string") {
          return contentValue.slice(0, 120);
        }
      }
    } catch {}
    return null;
  }

  private async hydrateTranscript(session: SessionRecord) {
    const filePath = this.getTranscriptPath(session);
    let content = "";
    try {
      content = await readFile(filePath, "utf8");
    } catch {
      return;
    }

    const seenResults = new Set<string>();
    for (const rawLine of content.split(/\n/)) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }
      let entry: Record<string, unknown> | null = null;
      try {
        entry = asObject(JSON.parse(line));
      } catch {
        continue;
      }
      const type = asString(entry?.type);
      if (type === "user") {
        const message = asObject(entry?.message);
        if (!message) {
          continue;
        }
        if (typeof message.content === "string") {
          this.db.appendSessionEntry(session.id, "user_message", {
            kind: "user_message",
            text: message.content,
            prompt: [
              {
                type: "text",
                text: message.content,
              },
            ],
          });
          continue;
        }

        for (const item of asArray(message.content)) {
          const contentPart = asObject(item);
          if (asString(contentPart?.type) !== "tool_result") {
            continue;
          }
          const toolUseId = asString(contentPart?.tool_use_id) ?? "";
          const dedupeKey = `${asString(entry?.uuid) ?? randomUUID()}:${toolUseId}`;
          if (seenResults.has(dedupeKey)) {
            continue;
          }
          seenResults.add(dedupeKey);
          this.db.appendSessionEntry(session.id, "tool_call_update", {
            kind: "tool_call_update",
            update: {
              toolCallId: toolUseId,
              kind: "tool_result",
              title: "Tool result",
              status: contentPart?.is_error === true ? "failed" : "completed",
              rawOutput: stringifyUnknown(contentPart?.content),
            },
          });
        }
        continue;
      }

      if (type !== "assistant") {
        continue;
      }

      const message = asObject(entry?.message);
      const messageId = asString(message?.id) ?? randomUUID();
      for (const block of asArray(message?.content)) {
        this.ingestAssistantBlock(session.id, messageId, asObject(block), false);
      }
    }
  }

  private handleClaudePayload(session: SessionRecord, payload: Record<string, unknown>) {
    const type = asString(payload.type);
    if (!type) {
      return;
    }

    if (type === "system" && asString(payload.subtype) === "init") {
      const sessionId = asString(payload.session_id);
      if (sessionId && sessionId !== session.agentSessionId) {
        this.rebindSession(session.id, sessionId);
      }

      const modeId = modeIdForPermissionMode(asString(payload.permissionMode));
      const currentModelId = asString(payload.model) ?? "sonnet";
      const capabilities = parseStoredSessionCapabilities(
        this.db.getSession(session.id)?.capabilitiesJson ?? session.capabilitiesJson,
      );
      const availableModels = [...(capabilities.models?.availableModels ?? [])];
      if (!availableModels.some((model) => model.modelId === currentModelId)) {
        availableModels.push({
          modelId: currentModelId,
          name: currentModelId,
          description: "Exact Claude model",
        });
      }
      this.updateStoredCapabilities(session.id, {
        models: {
          availableModels,
          currentModelId,
        },
        configOptions: [
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
        ],
        modes: {
          availableModes: capabilities.modes?.availableModes ?? buildClaudeCapabilities().modes?.availableModes ?? [],
          currentModeId: modeId,
        },
      });
      return;
    }

    if (type === "stream_event") {
      const event = asObject(payload.event);
      const eventType = asString(event?.type);
      if (!eventType) {
        return;
      }

      if (eventType === "message_start") {
        const messageId = asString(asObject(event?.message)?.id);
        if (messageId) {
          this.streamingMessageIds.set(session.id, messageId);
        }
        return;
      }

      if (eventType === "content_block_delta") {
        const delta = asObject(event?.delta);
        const deltaType = asString(delta?.type);
        const streamingMessageId = this.streamingMessageIds.get(session.id);
        if (deltaType === "text_delta") {
          const text = asString(delta?.text) ?? "";
          if (text) {
            if (streamingMessageId) {
              const accumulator =
                this.assistantText.get(streamingMessageId) ?? {
                  text: "",
                };
              accumulator.text += text;
              this.assistantText.set(streamingMessageId, accumulator);
            }
            this.emitSessionEntry(session.id, "agent_message_chunk", {
              kind: "agent_message_chunk",
              content: buildTextContent(text),
            });
          }
          return;
        }
        if (deltaType === "thinking_delta") {
          const text = asString(delta?.thinking) ?? "";
          if (text) {
            if (streamingMessageId) {
              const accumulator =
                this.assistantThinking.get(streamingMessageId) ?? {
                  text: "",
                };
              accumulator.text += text;
              this.assistantThinking.set(streamingMessageId, accumulator);
            }
            this.emitSessionEntry(session.id, "agent_thought_chunk", {
              kind: "agent_thought_chunk",
              content: buildTextContent(text),
            });
          }
        }
        return;
      }

      if (eventType === "message_stop") {
        this.streamingMessageIds.delete(session.id);
        return;
      }

      if (eventType === "message_delta") {
        const stopReason = asString(asObject(event?.delta)?.stop_reason);
        if (stopReason) {
          const active = this.activePrompts.get(session.id);
          if (active) {
            // Keep the last stop reason around until `result`.
            void active;
          }
        }
      }
      return;
    }

    if (type === "assistant") {
      const message = asObject(payload.message);
      const messageId = asString(message?.id) ?? randomUUID();
      for (const block of asArray(message?.content)) {
        this.ingestAssistantBlock(session.id, messageId, asObject(block), true);
      }
      return;
    }

    if (type === "user") {
      const message = asObject(payload.message);
      for (const block of asArray(message?.content)) {
        const item = asObject(block);
        if (asString(item?.type) !== "tool_result") {
          continue;
        }
        this.emitSessionEntry(session.id, "tool_call_update", {
          kind: "tool_call_update",
          update: {
            toolCallId: asString(item?.tool_use_id) ?? randomUUID(),
            kind: "tool_result",
            title: "Tool result",
            status: item?.is_error === true ? "failed" : "completed",
            rawOutput: stringifyUnknown(item?.content),
          },
        });
      }
      return;
    }

    if (type === "control_request") {
      const request = asObject(payload.request);
      const requestId = asString(payload.request_id);
      const subtype = asString(request?.subtype);
      const active = this.activePrompts.get(session.id);
      if (!requestId || !request || !active || subtype !== "can_use_tool") {
        return;
      }

      const toolName = asString(request.tool_name) ?? "tool";
      if (active.alwaysAllowTools.has(toolName)) {
        this.respondToControlRequest(active.child, requestId, {
          behavior: "allow",
          updatedInput: asObject(request.input) ?? {},
        });
        return;
      }

      this.emitPermissionRequest(
        session.id,
        {
          toolCall: {
            toolCallId: requestId,
            kind: toolName,
            title: toolName,
            rawInput: toStoredJson(request.input ?? {}),
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
          if (outcome.outcome === "selected" && outcome.optionId === "allow_always") {
            active.alwaysAllowTools.add(toolName);
          }
          this.respondToControlRequest(
            active.child,
            requestId,
            outcome.outcome === "selected" && outcome.optionId !== "reject_once"
              ? {
                  behavior: "allow",
                  updatedInput: asObject(request.input) ?? {},
                }
              : {
                  behavior: "deny",
                  message: "Denied by user",
                },
          );
        },
      );
      return;
    }

    if (type === "result") {
      const active = this.activePrompts.get(session.id);
      if (!active) {
        return;
      }
      const stopReason = asString(payload.stop_reason) ?? "completed";
      if (payload.is_error === true) {
        active.reject(
          new Error(asString(payload.result) ?? "Claude Code reported an error."),
        );
      } else {
        active.resolve({ stopReason });
      }
      return;
    }
  }

  private ingestAssistantBlock(
    localSessionId: string,
    messageId: string,
    block: Record<string, unknown> | null,
    broadcast: boolean,
  ) {
    if (!block) {
      return;
    }

    const append = (kind: string, payload: JsonObject) => {
      if (broadcast) {
        this.emitSessionEntry(localSessionId, kind, payload);
      } else {
        this.db.appendSessionEntry(localSessionId, kind, payload);
      }
    };

    const blockType = asString(block.type);
    if (blockType === "text") {
      const accumulator =
        this.assistantText.get(messageId) ?? {
          text: "",
        };
      const current = asString(block.text) ?? "";
      const delta = current.startsWith(accumulator.text)
        ? current.slice(accumulator.text.length)
        : current;
      accumulator.text = current;
      this.assistantText.set(messageId, accumulator);
      if (delta) {
        append("agent_message_chunk", {
          kind: "agent_message_chunk",
          content: buildTextContent(delta),
        });
      }
      return;
    }

    if (blockType === "thinking") {
      const accumulator =
        this.assistantThinking.get(messageId) ?? {
          text: "",
        };
      const current = asString(block.thinking) ?? "";
      const delta = current.startsWith(accumulator.text)
        ? current.slice(accumulator.text.length)
        : current;
      accumulator.text = current;
      this.assistantThinking.set(messageId, accumulator);
      if (delta) {
        append("agent_thought_chunk", {
          kind: "agent_thought_chunk",
          content: buildTextContent(delta),
        });
      }
      return;
    }

    if (blockType === "tool_use") {
      const toolCallId = asString(block.id) ?? randomUUID();
      if (this.seenToolCalls.has(toolCallId)) {
        return;
      }
      this.seenToolCalls.add(toolCallId);
      append("tool_call", {
        kind: "tool_call",
        update: {
          toolCallId,
          kind: asString(block.name) ?? "tool",
          title: asString(block.name) ?? "tool",
          status: "pending",
          rawInput: toStoredJson(block.input ?? {}),
        },
      });
    }
  }

  private respondToControlRequest(
    child: ChildProcessWithoutNullStreams,
    requestId: string,
    response: Record<string, unknown>,
  ) {
    child.stdin.write(
      `${JSON.stringify({
        type: "control_response",
        response: {
          subtype: "success",
          request_id: requestId,
          response,
        },
      })}\n`,
    );
  }
}
