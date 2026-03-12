function ref(name: string) {
  return { $ref: `#/components/schemas/${name}` };
}

function jsonResponse(
  description: string,
  schema: Record<string, unknown>,
  example?: unknown,
) {
  return {
    description,
    content: {
      "application/json": {
        schema,
        ...(example === undefined ? {} : { example }),
      },
    },
  };
}

function textResponse(
  description: string,
  contentType: string,
  schema: Record<string, unknown>,
  example?: string,
) {
  return {
    description,
    content: {
      [contentType]: {
        schema,
        ...(example === undefined ? {} : { example }),
      },
    },
  };
}

const bearerAuthParameter = {
  in: "header",
  name: "Authorization",
  required: true,
  schema: { type: "string" },
  description: "Bearer pairing token in the form `Bearer <token>`.",
} as const;

const errorExamples = {
  missingBearer: {
    error: "Missing bearer token.",
  },
  invalidBearer: {
    error: "Invalid bearer token.",
  },
  invalidToken: {
    error: "Invalid token.",
  },
  invalidPairingCode: {
    error: "Pairing code is invalid or expired.",
  },
  projectNotFound: {
    error: "Project not found.",
  },
  sessionNotFound: {
    error: "Session not found.",
  },
  messageNotFound: {
    error: "Message not found.",
  },
  permissionNotFound: {
    error: "Permission request not found.",
  },
  validation: {
    error: "Invalid request.",
    issues: [
      {
        path: "body.path",
        message: "Too small: expected string to have >=1 characters",
      },
    ],
  },
  invalidJson: {
    error: "Request body must be valid JSON.",
  },
  internal: {
    error: "Internal server error.",
  },
  notImplemented: {
    error: "PTY passthrough is not implemented yet.",
  },
} as const;

const examples = {
  v1Health: {
    healthy: true,
    version: "0.1.0",
    port: 4058,
    deviceName: "Vaibhavs-MacBook-Pro",
    deviceModel: "MacBookPro18,3",
    platform: "darwin",
  },
  discovery: {
    deviceName: "Vaibhavs-MacBook-Pro",
    deviceModel: "MacBookPro18,3",
    platform: "darwin",
    port: 4058,
    pairingRequired: true,
  },
  pairingCode: {
    code: "481902",
    expiresInSeconds: 300,
  },
  pairingRedeemRequest: {
    code: "481902",
    deviceName: "Vaibhav iPhone",
  },
  pairingRedeemResponse: {
    token: "2bb3f27f-1a9b-4c40-b7e7-1b2d5c4a9d31",
    device: {
      id: "f06f61a4-4bb6-4d64-85db-03ce49dfbc31",
      name: "Vaibhav iPhone",
    },
  },
  realtimeSummary: {
    note: "WebSocket upgrade endpoint intentionally not expanded in this OpenAPI document.",
  },
  agentDescriptor: {
    id: "codex",
    name: "Codex CLI",
    kind: "adapter",
    source: "acp",
    installState: "detected",
    binaryPath: "/usr/local/bin/codex-acp",
    version: null,
    metadata: {
      args: [],
      commandCandidates: ["codex-acp"],
    },
    authMethods: [
      {
        id: "openai_api_key",
        type: "env_var",
        name: "OpenAI API Key",
        vars: [
          {
            name: "OPENAI_API_KEY",
            label: "API key",
            optional: false,
            secret: true,
          },
        ],
      },
    ],
    capabilities: {
      loadSession: true,
      promptCapabilities: {
        image: false,
        audio: false,
        embeddedContext: true,
      },
    },
  },
  initializeAgent: {
    authMethods: [
      {
        id: "openai_api_key",
        type: "env_var",
        name: "OpenAI API Key",
        vars: [
          {
            name: "OPENAI_API_KEY",
            label: "API key",
            optional: false,
            secret: true,
          },
        ],
      },
    ],
    capabilities: {
      loadSession: true,
      promptCapabilities: {
        image: false,
        audio: false,
      },
    },
  },
  authenticateAgentRequest: {
    methodId: "openai_api_key",
  },
  authenticateAgentResponse: {},
  apiProject: {
    id: "c935ef71-91f7-4c95-8f74-a3456df11f11",
    rootPath: "/Users/vaibhav/Developer/Personal/mocode",
    detectedName: "mocode",
    displayName: "moCODE",
    preferredAgentId: "codex",
    createdAt: "2026-03-11T12:30:10.000Z",
    updatedAt: "2026-03-11T12:32:41.000Z",
    lastOpenedAt: "2026-03-11T12:32:41.000Z",
    name: "moCODE",
    sessionCount: 2,
  },
  apiSession: {
    id: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
    projectId: "c935ef71-91f7-4c95-8f74-a3456df11f11",
    agentId: "codex",
    agentSessionId: "session_01JPAATF3S1V46X7P02N7R7N4R",
    cwd: "/Users/vaibhav/Developer/Personal/mocode",
    title: "Document the CLI APIs",
    status: "idle",
    controllerDeviceId: "f06f61a4-4bb6-4d64-85db-03ce49dfbc31",
    createdAt: "2026-03-11T12:32:51.000Z",
    updatedAt: "2026-03-11T12:37:12.000Z",
    lastStopReason: "completed",
    capabilitiesJson:
      "{\"authMethods\":[],\"agentCapabilities\":{\"loadSession\":true},\"modes\":[{\"id\":\"build\",\"name\":\"Build\"}],\"configOptions\":null}",
  },
  apiSessionEntry: {
    id: "e2eb7f45-8ec2-4c64-8978-a0952f9634fb",
    seq: 1,
    kind: "user_message",
    payload: {
      kind: "user_message",
      text: "Document every CLI API endpoint with examples.",
    },
    createdAt: "2026-03-11T12:33:02.000Z",
  },
  globalHealth: {
    healthy: true,
    version: "0.1.0",
  },
  pathInfo: {
    home: "/Users/vaibhav",
    state: "/Users/vaibhav/Library/Application Support/mocode",
    config: "/Users/vaibhav/Library/Application Support/mocode/config",
    worktree: "/Users/vaibhav/Developer/Personal/mocode",
    directory: "/Users/vaibhav/Developer/Personal/mocode",
  },
  vcsInfo: {
    branch: "main",
  },
  command: {
    name: "run",
    description: "Ask the active session to execute a command",
    template: "/run <command>",
    hints: ["Provide a shell command after /run"],
  },
  agentPreset: {
    name: "Build",
    mode: "build",
    native: true,
  },
  providerList: {
    all: [
      {
        id: "local",
        name: "Local Agents",
        models: [
          {
            id: "codex",
            name: "Codex CLI",
            family: "ACP",
            status: "ready",
            reasoning: true,
          },
        ],
      },
    ],
    default: {
      providerID: "local",
      modelID: "codex",
    },
    connected: ["local"],
  },
  appConfig: {
    default_agent: "codex",
    username: "vaibhav",
  },
  fileNode: {
    name: "apps",
    path: "apps",
    absolute: "/Users/vaibhav/Developer/Personal/mocode/apps",
    type: "directory",
    ignored: false,
  },
  legacyProject: {
    id: "c935ef71-91f7-4c95-8f74-a3456df11f11",
    worktree: "/Users/vaibhav/Developer/Personal/mocode",
    vcs: "git",
    name: "moCODE",
    time: {
      created: 1741696210000,
      updated: 1741696361000,
      initialized: 1741696361000,
    },
    sandboxes: [],
  },
  legacySession: {
    id: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
    slug: "7644b3a7",
    projectID: "c935ef71-91f7-4c95-8f74-a3456df11f11",
    directory: "/Users/vaibhav/Developer/Personal/mocode",
    title: "Document the CLI APIs",
    version: "acp",
    time: {
      created: 1741696371000,
      updated: 1741696632000,
    },
  },
  sessionStatusMap: {
    "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5": {
      type: "idle",
    },
  },
  messageWrapper: {
    info: {
      id: "assistant:e2eb7f45-8ec2-4c64-8978-a0952f9634fb",
      sessionID: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
      role: "assistant",
      parentID: "e2eb7f45-8ec2-4c64-8978-a0952f9634fb",
      modelID: "default",
      providerID: "local",
      mode: "build",
      agent: "codex",
      path: {
        cwd: "/Users/vaibhav/Developer/Personal/mocode",
        root: "/Users/vaibhav/Developer/Personal/mocode",
      },
      cost: 0,
      tokens: {
        input: 0,
        output: 0,
        reasoning: 0,
        cache: {
          read: 0,
          write: 0,
        },
      },
      time: {
        created: 1741696380000,
        completed: 1741696385000,
      },
    },
    parts: [
      {
        id: "assistant:e2eb7f45-8ec2-4c64-8978-a0952f9634fb:text",
        sessionID: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
        messageID: "assistant:e2eb7f45-8ec2-4c64-8978-a0952f9634fb",
        type: "text",
        text: "I mapped the daemon endpoints and prepared an OpenAPI spec.",
        time: {
          start: 1741696380000,
          end: 1741696385000,
        },
      },
      {
        id: "assistant:e2eb7f45-8ec2-4c64-8978-a0952f9634fb:tool:call_1",
        sessionID: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
        messageID: "assistant:e2eb7f45-8ec2-4c64-8978-a0952f9634fb",
        type: "tool",
        callID: "call_1",
        tool: "read_file",
        state: {
          status: "completed",
          input: {
            path: "apps/cli/src/daemon.ts",
          },
          output: "Route table inspected successfully.",
        },
      },
    ],
  },
  permissionRequest: {
    id: "permission_01",
    sessionID: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
    permission: "write_file",
    patterns: ["apps/cli/src/**"],
    metadata: {
      toolCall: {
        kind: "write_file",
        title: "Write file",
        toolCallId: "call_1",
      },
      options: [
        {
          optionId: "once",
          name: "Allow once",
          kind: "allow_once",
        },
        {
          optionId: "always",
          name: "Always allow",
          kind: "allow_always",
        },
      ],
    },
    always: ["allow_always"],
    tool: {
      messageID: "assistant:7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
      callID: "call_1",
    },
  },
  questionRequest: {
    id: "question_01",
    sessionID: "7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5",
    questions: [
      {
        header: "Auth",
        question: "Which token should be used?",
        options: [
          {
            label: "Development",
            description: "Use the development token stored locally.",
          },
          {
            label: "Production",
            description: "Use the production token from secure storage.",
          },
        ],
      },
    ],
  },
  fileDiff: {
    file: "apps/cli/src/daemon.ts",
    before: "@@ -1,3 +1,5 @@\n",
    after: "@@ -1,3 +1,12 @@\n",
    additions: 9,
    deletions: 0,
    status: "modified",
  },
  todo: {
    id: "todo_01",
    content: "Write OpenAPI spec",
    status: "completed",
    priority: "high",
  },
  sseStream: "retry: 3000\n: connected\n\ndata: {\"payload\":{\"type\":\"session.created\",\"properties\":{\"info\":{\"id\":\"7644b3a7-f7a0-4fa9-b4f5-96646ff6d6a5\",\"title\":\"Document the CLI APIs\"}}},\"directory\":\"/Users/vaibhav/Developer/Personal/mocode\"}\n\n",
  ok: {
    ok: true,
  },
} as const;

export function buildOpenApiSpec(port: number) {
  const spec: any = {
    openapi: "3.0.3",
    info: {
      title: "moCODE CLI Daemon API",
      version: "0.1.0",
      description:
        "Complete HTTP documentation for the local moCODE CLI daemon. This spec covers the current REST and SSE surface, including both `/v1/*` endpoints and the legacy compatibility endpoints consumed by the mobile app. WebSocket endpoints are listed for discoverability but their message protocols are intentionally not expanded here.",
    },
    servers: [
      {
        url: "/",
        description: "Current daemon origin",
      },
      {
        url: `http://127.0.0.1:${port}`,
        description: "Default local daemon address",
      },
    ],
    tags: [
      { name: "Docs", description: "Documentation endpoints served by the daemon." },
      { name: "Daemon", description: "Health and discovery endpoints." },
      { name: "Pairing", description: "Local device pairing and token issuance." },
      { name: "Realtime", description: "Streaming endpoints. WebSockets are only summarized." },
      { name: "Agents", description: "ACP agent discovery and authentication." },
      { name: "Projects", description: "Structured `/v1/*` project endpoints." },
      { name: "Sessions", description: "Structured `/v1/*` session endpoints." },
      { name: "Legacy App", description: "Compatibility endpoints used by the mobile app." },
      { name: "Filesystem", description: "Path, file browser, and file search endpoints." },
      { name: "Permissions", description: "Pending permission and question queues." },
      { name: "PTY", description: "PTY compatibility endpoints. Most are placeholders today." },
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "Token",
          description: "Pairing token returned by `POST /v1/pairing/code/redeem`.",
        },
      },
      schemas: {
        ErrorResponse: {
          type: "object",
          properties: {
            error: { type: "string" },
            issues: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  path: { type: "string" },
                  message: { type: "string" },
                },
                required: ["path", "message"],
              },
            },
          },
          required: ["error"],
        },
        BooleanOk: {
          type: "object",
          properties: {
            ok: { type: "boolean" },
          },
          required: ["ok"],
        },
        V1Health: {
          type: "object",
          properties: {
            healthy: { type: "boolean" },
            version: { type: "string" },
            port: { type: "integer" },
            deviceName: { type: "string" },
            deviceModel: { type: "string", nullable: true },
            platform: { type: "string" },
          },
          required: [
            "healthy",
            "version",
            "port",
            "deviceName",
            "deviceModel",
            "platform",
          ],
        },
        DiscoveryResponse: {
          type: "object",
          properties: {
            deviceName: { type: "string" },
            deviceModel: { type: "string", nullable: true },
            platform: { type: "string" },
            port: { type: "integer" },
            pairingRequired: { type: "boolean" },
          },
          required: [
            "deviceName",
            "deviceModel",
            "platform",
            "port",
            "pairingRequired",
          ],
        },
        PairingCodeResponse: {
          type: "object",
          properties: {
            code: {
              type: "string",
              pattern: "^[0-9]{6}$",
            },
            expiresInSeconds: { type: "integer" },
          },
          required: ["code", "expiresInSeconds"],
        },
        PairingRedeemRequest: {
          type: "object",
          properties: {
            code: { type: "string", minLength: 6 },
            deviceName: { type: "string", minLength: 1, maxLength: 120 },
          },
          required: ["code", "deviceName"],
        },
        PairedDevice: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
          },
          required: ["id", "name"],
        },
        PairingRedeemResponse: {
          type: "object",
          properties: {
            token: { type: "string" },
            device: ref("PairedDevice"),
          },
          required: ["token", "device"],
        },
        AuthMethod: {
          oneOf: [
            {
              type: "object",
              properties: {
                id: { type: "string" },
                type: { type: "string", enum: ["env_var"] },
                name: { type: "string" },
                description: { type: "string", nullable: true },
                link: { type: "string", nullable: true },
                vars: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      name: { type: "string" },
                      label: { type: "string", nullable: true },
                      optional: { type: "boolean" },
                      secret: { type: "boolean" },
                    },
                    required: ["name"],
                  },
                },
              },
              required: ["id", "type", "name", "vars"],
            },
            {
              type: "object",
              properties: {
                id: { type: "string" },
                type: { type: "string", enum: ["terminal"] },
                name: { type: "string" },
                description: { type: "string", nullable: true },
                args: {
                  type: "array",
                  items: { type: "string" },
                },
                env: {
                  type: "object",
                  additionalProperties: { type: "string" },
                },
              },
              required: ["id", "type", "name"],
            },
            {
              type: "object",
              properties: {
                id: { type: "string" },
                name: { type: "string" },
                description: { type: "string", nullable: true },
              },
              required: ["id", "name"],
            },
          ],
        },
        AgentDescriptor: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
            kind: { type: "string" },
            source: { type: "string" },
            installState: {
              type: "string",
              enum: ["detected", "configured", "unavailable"],
            },
            binaryPath: { type: "string", nullable: true },
            version: { type: "string", nullable: true },
            metadata: {
              type: "object",
              additionalProperties: true,
            },
            authMethods: {
              type: "array",
              items: ref("AuthMethod"),
            },
            capabilities: {
              type: "object",
              nullable: true,
              additionalProperties: true,
            },
          },
          required: [
            "id",
            "name",
            "kind",
            "source",
            "installState",
            "binaryPath",
            "version",
            "metadata",
            "authMethods",
            "capabilities",
          ],
        },
        AgentListResponse: {
          type: "object",
          properties: {
            agents: {
              type: "array",
              items: ref("AgentDescriptor"),
            },
          },
          required: ["agents"],
        },
        InitializeAgentResponse: {
          type: "object",
          properties: {
            authMethods: {
              type: "array",
              items: ref("AuthMethod"),
            },
            capabilities: {
              type: "object",
              nullable: true,
              additionalProperties: true,
            },
          },
          required: ["authMethods", "capabilities"],
        },
        AuthenticateAgentRequest: {
          type: "object",
          properties: {
            methodId: { type: "string" },
          },
          required: ["methodId"],
        },
        AuthenticateAgentResponse: {
          type: "object",
          additionalProperties: true,
        },
        ApiProject: {
          type: "object",
          properties: {
            id: { type: "string" },
            rootPath: { type: "string" },
            detectedName: { type: "string" },
            displayName: { type: "string", nullable: true },
            preferredAgentId: { type: "string", nullable: true },
            createdAt: { type: "string", format: "date-time" },
            updatedAt: { type: "string", format: "date-time" },
            lastOpenedAt: { type: "string", format: "date-time", nullable: true },
            name: { type: "string" },
            sessionCount: { type: "integer" },
          },
          required: [
            "id",
            "rootPath",
            "detectedName",
            "displayName",
            "preferredAgentId",
            "createdAt",
            "updatedAt",
            "lastOpenedAt",
            "name",
            "sessionCount",
          ],
        },
        ApiProjectListResponse: {
          type: "object",
          properties: {
            projects: {
              type: "array",
              items: ref("ApiProject"),
            },
          },
          required: ["projects"],
        },
        OpenProjectRequest: {
          type: "object",
          properties: {
            path: { type: "string", minLength: 1 },
          },
          required: ["path"],
        },
        ApiSession: {
          type: "object",
          properties: {
            id: { type: "string" },
            projectId: { type: "string" },
            agentId: { type: "string" },
            agentSessionId: { type: "string" },
            cwd: { type: "string" },
            title: { type: "string", nullable: true },
            status: { type: "string" },
            controllerDeviceId: { type: "string", nullable: true },
            createdAt: { type: "string", format: "date-time" },
            updatedAt: { type: "string", format: "date-time" },
            lastStopReason: { type: "string", nullable: true },
            capabilitiesJson: { type: "string", nullable: true },
          },
          required: [
            "id",
            "projectId",
            "agentId",
            "agentSessionId",
            "cwd",
            "title",
            "status",
            "controllerDeviceId",
            "createdAt",
            "updatedAt",
            "lastStopReason",
            "capabilitiesJson",
          ],
        },
        ApiProjectDetailResponse: {
          type: "object",
          properties: {
            project: ref("ApiProject"),
            sessions: {
              type: "array",
              items: ref("ApiSession"),
            },
          },
          required: ["project", "sessions"],
        },
        ProjectSearchResponse: {
          type: "object",
          properties: {
            known: {
              type: "array",
              items: ref("ApiProject"),
            },
            discovered: {
              type: "array",
              items: { type: "string" },
            },
          },
          required: ["known", "discovered"],
        },
        UpdateProjectRequest: {
          type: "object",
          properties: {
            displayName: { type: "string", nullable: true },
            preferredAgentId: { type: "string", nullable: true },
          },
        },
        SessionsListResponse: {
          type: "object",
          properties: {
            sessions: {
              type: "array",
              items: ref("ApiSession"),
            },
          },
          required: ["sessions"],
        },
        ApiSessionEntry: {
          type: "object",
          properties: {
            id: { type: "string" },
            seq: { type: "integer" },
            kind: { type: "string" },
            payload: {
              type: "object",
              additionalProperties: true,
            },
            createdAt: { type: "string", format: "date-time" },
          },
          required: ["id", "seq", "kind", "payload", "createdAt"],
        },
        SessionSnapshotResponse: {
          type: "object",
          properties: {
            session: ref("ApiSession"),
            entries: {
              type: "array",
              items: ref("ApiSessionEntry"),
            },
          },
          required: ["session", "entries"],
        },
        GlobalHealth: {
          type: "object",
          properties: {
            healthy: { type: "boolean" },
            version: { type: "string" },
          },
          required: ["healthy", "version"],
        },
        PathInfo: {
          type: "object",
          properties: {
            home: { type: "string" },
            state: { type: "string" },
            config: { type: "string" },
            worktree: { type: "string" },
            directory: { type: "string" },
          },
          required: ["home", "state", "config", "worktree", "directory"],
        },
        VcsInfo: {
          type: "object",
          properties: {
            branch: { type: "string" },
          },
          required: ["branch"],
        },
        CommandDescriptor: {
          type: "object",
          properties: {
            name: { type: "string" },
            description: { type: "string", nullable: true },
            template: { type: "string" },
            hints: {
              type: "array",
              items: { type: "string" },
            },
          },
          required: ["name", "template", "hints"],
        },
        AgentPreset: {
          type: "object",
          properties: {
            name: { type: "string" },
            mode: { type: "string" },
            native: { type: "boolean", nullable: true },
          },
          required: ["name", "mode"],
        },
        ProviderListResponse: {
          type: "object",
          properties: {
            all: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  id: { type: "string" },
                  name: { type: "string" },
                  models: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        id: { type: "string" },
                        name: { type: "string" },
                        family: { type: "string", nullable: true },
                        status: { type: "string", nullable: true },
                        reasoning: { type: "boolean", nullable: true },
                      },
                      required: ["id"],
                    },
                  },
                },
                required: ["id", "name", "models"],
              },
            },
            default: {
              type: "object",
              additionalProperties: { type: "string" },
            },
            connected: {
              type: "array",
              items: { type: "string" },
            },
          },
          required: ["all", "default", "connected"],
        },
        AppConfig: {
          type: "object",
          properties: {
            default_agent: { type: "string", nullable: true },
            username: { type: "string", nullable: true },
          },
          additionalProperties: true,
        },
        FileNode: {
          type: "object",
          properties: {
            name: { type: "string" },
            path: { type: "string" },
            absolute: { type: "string" },
            type: { type: "string", enum: ["directory", "file"] },
            ignored: { type: "boolean" },
          },
          required: ["name", "path", "absolute", "type", "ignored"],
        },
        LegacyProject: {
          type: "object",
          properties: {
            id: { type: "string" },
            worktree: { type: "string" },
            vcs: { type: "string", nullable: true },
            name: { type: "string", nullable: true },
            time: {
              type: "object",
              properties: {
                created: { type: "integer" },
                updated: { type: "integer" },
                initialized: { type: "integer" },
              },
              required: ["created"],
            },
            sandboxes: {
              type: "array",
              items: { type: "string" },
            },
          },
          required: ["id", "worktree", "time", "sandboxes"],
        },
        LegacySession: {
          type: "object",
          properties: {
            id: { type: "string" },
            slug: { type: "string" },
            projectID: { type: "string" },
            directory: { type: "string" },
            title: { type: "string" },
            version: { type: "string" },
            time: {
              type: "object",
              properties: {
                created: { type: "integer" },
                updated: { type: "integer" },
              },
              required: ["created", "updated"],
            },
          },
          required: ["id", "slug", "projectID", "directory", "title", "version", "time"],
        },
        LegacySessionStatus: {
          type: "object",
          properties: {
            type: { type: "string", enum: ["idle", "busy"] },
          },
          required: ["type"],
        },
        LegacySessionStatusMap: {
          type: "object",
          additionalProperties: ref("LegacySessionStatus"),
        },
        LegacyTextPart: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            messageID: { type: "string" },
            type: { type: "string", enum: ["text"] },
            text: { type: "string" },
            synthetic: { type: "boolean" },
            time: {
              type: "object",
              properties: {
                start: { type: "integer" },
                end: { type: "integer", nullable: true },
              },
              required: ["start"],
            },
          },
          required: ["id", "sessionID", "messageID", "type", "text"],
        },
        LegacyReasoningPart: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            messageID: { type: "string" },
            type: { type: "string", enum: ["reasoning"] },
            text: { type: "string" },
          },
          required: ["id", "sessionID", "messageID", "type", "text"],
        },
        LegacyToolPart: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            messageID: { type: "string" },
            type: { type: "string", enum: ["tool"] },
            callID: { type: "string" },
            tool: { type: "string" },
            state: {
              type: "object",
              additionalProperties: true,
            },
          },
          required: ["id", "sessionID", "messageID", "type", "callID", "tool", "state"],
        },
        LegacyUserMessageInfo: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            role: { type: "string", enum: ["user"] },
            agent: { type: "string", nullable: true },
            time: {
              type: "object",
              properties: {
                created: { type: "integer" },
                completed: { type: "integer", nullable: true },
              },
              required: ["created"],
            },
          },
          required: ["id", "sessionID", "role", "time"],
        },
        LegacyAssistantMessageInfo: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            role: { type: "string", enum: ["assistant"] },
            parentID: { type: "string", nullable: true },
            modelID: { type: "string" },
            providerID: { type: "string" },
            mode: { type: "string" },
            agent: { type: "string", nullable: true },
            path: {
              type: "object",
              properties: {
                cwd: { type: "string" },
                root: { type: "string" },
              },
              required: ["cwd", "root"],
            },
            cost: { type: "number" },
            tokens: {
              type: "object",
              properties: {
                input: { type: "integer" },
                output: { type: "integer" },
                reasoning: { type: "integer" },
                cache: {
                  type: "object",
                  properties: {
                    read: { type: "integer" },
                    write: { type: "integer" },
                  },
                  required: ["read", "write"],
                },
              },
              required: ["input", "output", "reasoning", "cache"],
            },
            time: {
              type: "object",
              properties: {
                created: { type: "integer" },
                completed: { type: "integer", nullable: true },
              },
              required: ["created"],
            },
          },
          required: [
            "id",
            "sessionID",
            "role",
            "modelID",
            "providerID",
            "mode",
            "cost",
            "tokens",
            "time",
          ],
        },
        MessageWrapper: {
          type: "object",
          properties: {
            info: {
              oneOf: [ref("LegacyUserMessageInfo"), ref("LegacyAssistantMessageInfo")],
            },
            parts: {
              type: "array",
              items: {
                oneOf: [ref("LegacyTextPart"), ref("LegacyReasoningPart"), ref("LegacyToolPart")],
              },
            },
          },
          required: ["info", "parts"],
        },
        MessageEnvelopeRequest: {
          type: "object",
          properties: {
            parts: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: true,
              },
            },
            model: {
              type: "object",
              properties: {
                providerID: { type: "string" },
                modelID: { type: "string" },
              },
            },
            agent: { type: "string" },
            variant: { type: "string" },
          },
          required: ["parts"],
        },
        SessionCommandRequest: {
          type: "object",
          properties: {
            command: { type: "string" },
            arguments: { type: "string" },
            agent: { type: "string" },
            model: { type: "string" },
            variant: { type: "string" },
          },
          required: ["command", "arguments"],
        },
        PermissionRequest: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            permission: { type: "string" },
            patterns: {
              type: "array",
              items: { type: "string" },
            },
            metadata: {
              type: "object",
              additionalProperties: true,
            },
            always: {
              type: "array",
              items: { type: "string" },
            },
            tool: {
              type: "object",
              nullable: true,
              properties: {
                messageID: { type: "string" },
                callID: { type: "string" },
              },
              required: ["messageID", "callID"],
            },
          },
          required: ["id", "sessionID", "permission", "patterns", "metadata", "always"],
        },
        PermissionReplyRequest: {
          type: "object",
          properties: {
            reply: {
              type: "string",
              enum: ["allow", "always", "reject"],
            },
          },
          required: ["reply"],
        },
        QuestionRequest: {
          type: "object",
          properties: {
            id: { type: "string" },
            sessionID: { type: "string" },
            questions: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  question: { type: "string" },
                  header: { type: "string" },
                  options: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        label: { type: "string" },
                        description: { type: "string" },
                      },
                      required: ["label", "description"],
                    },
                  },
                  multiple: { type: "boolean", nullable: true },
                  custom: { type: "boolean", nullable: true },
                },
                required: ["question", "header", "options"],
              },
            },
          },
          required: ["id", "sessionID", "questions"],
        },
        QuestionReplyRequest: {
          type: "object",
          properties: {
            answers: {
              type: "array",
              items: {
                type: "array",
                items: { type: "string" },
              },
            },
          },
          required: ["answers"],
        },
        FileDiff: {
          type: "object",
          properties: {
            file: { type: "string" },
            before: { type: "string" },
            after: { type: "string" },
            additions: { type: "integer" },
            deletions: { type: "integer" },
            status: { type: "string", nullable: true },
          },
          required: ["file", "before", "after", "additions", "deletions"],
        },
        TodoItem: {
          type: "object",
          properties: {
            id: { type: "string" },
            content: { type: "string" },
            status: { type: "string" },
            priority: { type: "string" },
          },
          required: ["id", "content", "status", "priority"],
        },
      },
    },
    paths: {
      "/api/openapi.json": {
        get: {
          tags: ["Docs"],
          operationId: "docs.openapi",
          summary: "Get the raw OpenAPI 3.0 document",
          responses: {
            "200": jsonResponse(
              "OpenAPI document",
              {
                type: "object",
                additionalProperties: true,
              },
            ),
          },
        },
      },
      "/api/docs": {
        get: {
          tags: ["Docs"],
          operationId: "docs.ui",
          summary: "Open the interactive Swagger UI page",
          responses: {
            "200": textResponse(
              "Swagger UI HTML page",
              "text/html",
              { type: "string" },
            ),
          },
        },
      },
      "/v1/health": {
        get: {
          tags: ["Daemon"],
          operationId: "v1.health",
          summary: "Get daemon health and identity",
          responses: {
            "200": jsonResponse("Daemon status", ref("V1Health"), examples.v1Health),
          },
        },
      },
      "/v1/discovery": {
        get: {
          tags: ["Daemon"],
          operationId: "v1.discovery",
          summary: "Get LAN discovery metadata",
          responses: {
            "200": jsonResponse(
              "Device discovery metadata",
              ref("DiscoveryResponse"),
              examples.discovery,
            ),
          },
        },
      },
      "/v1/pairing/code": {
        post: {
          tags: ["Pairing"],
          operationId: "v1.pairing.code.create",
          summary: "Create a short-lived pairing code",
          description:
            "This route only succeeds from loopback addresses such as `127.0.0.1` or `localhost`.",
          responses: {
            "200": jsonResponse(
              "Pairing code created",
              ref("PairingCodeResponse"),
              examples.pairingCode,
            ),
            "403": jsonResponse(
              "Request did not originate from loopback",
              ref("ErrorResponse"),
              { error: "Pairing codes may only be created locally." },
            ),
            "500": jsonResponse(
              "Unexpected daemon failure",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/v1/pairing/code/redeem": {
        post: {
          tags: ["Pairing"],
          operationId: "v1.pairing.code.redeem",
          summary: "Redeem a pairing code for a bearer token",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("PairingRedeemRequest"),
                example: examples.pairingRedeemRequest,
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Pairing code redeemed",
              ref("PairingRedeemResponse"),
              examples.pairingRedeemResponse,
            ),
            "400": jsonResponse(
              "Pairing code is invalid, expired, malformed, or JSON could not be parsed",
              ref("ErrorResponse"),
              errorExamples.invalidPairingCode,
            ),
            "500": jsonResponse(
              "Unexpected daemon failure",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/v1/realtime": {
        get: {
          tags: ["Realtime"],
          operationId: "v1.realtime.summary",
          summary: "WebSocket session stream",
          description:
            "WebSocket upgrade endpoint. The daemon expects a valid pairing token in the `token` query parameter. The message protocol is intentionally omitted from this document.",
          parameters: [
            {
              in: "query",
              name: "token",
              required: true,
              schema: { type: "string" },
              description: "Pairing token issued by `/v1/pairing/code/redeem`.",
            },
          ],
          responses: {
            "101": {
              description: "WebSocket upgrade completed.",
            },
            "400": jsonResponse(
              "Upgrade failed after authentication succeeded",
              ref("ErrorResponse"),
              { error: "WebSocket upgrade failed." },
            ),
            "401": jsonResponse(
              "Token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidToken,
            ),
          },
        },
      },
      "/v1/events": {
        get: {
          tags: ["Realtime"],
          operationId: "v1.events.subscribe",
          summary: "Subscribe to session events",
          description:
            "Server-sent event stream for session-scoped realtime updates. Pass one or more session IDs as a comma-separated `sessionId` query value.",
          parameters: [
            {
              in: "query",
              name: "sessionId",
              schema: { type: "string" },
              description:
                "Comma-separated local session IDs to receive `session_update` and `permission_request` events for.",
            },
            bearerAuthParameter,
          ],
          responses: {
            "200": textResponse(
              "Server-sent event stream",
              "text/event-stream",
              { type: "string" },
              examples.sseStream,
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
          },
        },
      },
      "/v1/agents": {
        get: {
          tags: ["Agents"],
          operationId: "v1.agents.list",
          summary: "List detected ACP agents",
          security: [{ bearerAuth: [] }],
          responses: {
            "200": jsonResponse(
              "Detected agents",
              ref("AgentListResponse"),
              { agents: [examples.agentDescriptor] },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.missingBearer,
            ),
            "500": jsonResponse(
              "Unexpected daemon failure",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/v1/agents/{agentId}/initialize": {
        post: {
          tags: ["Agents"],
          operationId: "v1.agents.initialize",
          summary: "Start an agent runtime and read its capabilities",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "path",
              name: "agentId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Runtime initialized",
              ref("InitializeAgentResponse"),
              examples.initializeAgent,
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "500": jsonResponse(
              "Agent binary unavailable or startup failed",
              ref("ErrorResponse"),
              {
                error: "Internal server error.",
              },
            ),
          },
        },
      },
      "/v1/agents/{agentId}/authenticate": {
        post: {
          tags: ["Agents"],
          operationId: "v1.agents.authenticate",
          summary: "Invoke an agent authentication method",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "path",
              name: "agentId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("AuthenticateAgentRequest"),
                example: examples.authenticateAgentRequest,
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Authentication completed",
              ref("AuthenticateAgentResponse"),
              examples.authenticateAgentResponse,
            ),
            "400": jsonResponse(
              "Malformed JSON request body",
              ref("ErrorResponse"),
              errorExamples.invalidJson,
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "500": jsonResponse(
              "Agent runtime error",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/v1/projects": {
        get: {
          tags: ["Projects"],
          operationId: "v1.projects.list",
          summary: "List structured projects",
          security: [{ bearerAuth: [] }],
          responses: {
            "200": jsonResponse(
              "Projects returned",
              ref("ApiProjectListResponse"),
              { projects: [examples.apiProject] },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.missingBearer,
            ),
          },
        },
      },
      "/v1/projects/open": {
        post: {
          tags: ["Projects"],
          operationId: "v1.projects.open",
          summary: "Open or register a project by filesystem path",
          security: [{ bearerAuth: [] }],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("OpenProjectRequest"),
                example: {
                  path: "/Users/vaibhav/Developer/Personal/mocode",
                },
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Project opened",
              ref("ApiProjectDetailResponse"),
              {
                project: examples.apiProject,
                sessions: [examples.apiSession],
              },
            ),
            "400": jsonResponse(
              "Path is not a directory or validation failed",
              ref("ErrorResponse"),
              { error: "Path must be a directory." },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "404": jsonResponse(
              "Requested path does not exist",
              ref("ErrorResponse"),
              { error: "Requested path was not found." },
            ),
            "500": jsonResponse(
              "Unexpected daemon failure",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/v1/projects/search": {
        get: {
          tags: ["Projects"],
          operationId: "v1.projects.search",
          summary: "Search indexed and discoverable project directories",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "query",
              name: "q",
              schema: { type: "string" },
              description: "Case-insensitive search term.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Search results returned",
              ref("ProjectSearchResponse"),
              {
                known: [examples.apiProject],
                discovered: [
                  "/Users/vaibhav/Developer/Personal/mocode",
                  "/Users/vaibhav/Developer/Work/client-app",
                ],
              },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
          },
        },
      },
      "/v1/projects/{projectId}": {
        get: {
          tags: ["Projects"],
          operationId: "v1.projects.get",
          summary: "Get one structured project and its sessions",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "path",
              name: "projectId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Project returned",
              ref("ApiProjectDetailResponse"),
              {
                project: examples.apiProject,
                sessions: [examples.apiSession],
              },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "404": jsonResponse(
              "Project ID was not found",
              ref("ErrorResponse"),
              errorExamples.projectNotFound,
            ),
          },
        },
        patch: {
          tags: ["Projects"],
          operationId: "v1.projects.update",
          summary: "Update a structured project",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "path",
              name: "projectId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("UpdateProjectRequest"),
                example: {
                  displayName: "moCODE",
                  preferredAgentId: "codex",
                },
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Project updated",
              {
                type: "object",
                properties: {
                  project: ref("ApiProject"),
                },
                required: ["project"],
              },
              {
                project: examples.apiProject,
              },
            ),
            "400": jsonResponse(
              "Validation failed or JSON could not be parsed",
              ref("ErrorResponse"),
              errorExamples.validation,
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "404": jsonResponse(
              "Project ID was not found",
              ref("ErrorResponse"),
              errorExamples.projectNotFound,
            ),
          },
        },
      },
      "/v1/sessions": {
        get: {
          tags: ["Sessions"],
          operationId: "v1.sessions.list",
          summary: "List structured sessions",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "query",
              name: "projectId",
              schema: { type: "string" },
              description: "Optional project filter.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Sessions returned",
              ref("SessionsListResponse"),
              {
                sessions: [examples.apiSession],
              },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
          },
        },
      },
      "/v1/sessions/{sessionId}": {
        get: {
          tags: ["Sessions"],
          operationId: "v1.sessions.get",
          summary: "Get a structured session snapshot",
          security: [{ bearerAuth: [] }],
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Snapshot returned",
              ref("SessionSnapshotResponse"),
              {
                session: examples.apiSession,
                entries: [examples.apiSessionEntry],
              },
            ),
            "401": jsonResponse(
              "Bearer token missing or invalid",
              ref("ErrorResponse"),
              errorExamples.invalidBearer,
            ),
            "404": jsonResponse(
              "Session ID was not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
          },
        },
      },
      "/event": {
        get: {
          tags: ["Realtime", "Legacy App"],
          operationId: "legacy.events.subscribe",
          summary: "Subscribe to server-sent events",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional directory filter applied by the daemon.",
            },
          ],
          responses: {
            "200": textResponse(
              "Server-sent event stream",
              "text/event-stream",
              { type: "string" },
              examples.sseStream,
            ),
          },
        },
      },
      "/global/health": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.global.health",
          summary: "Get legacy health payload",
          responses: {
            "200": jsonResponse(
              "Global health returned",
              ref("GlobalHealth"),
              examples.globalHealth,
            ),
          },
        },
      },
      "/path": {
        get: {
          tags: ["Filesystem", "Legacy App"],
          operationId: "legacy.path.get",
          summary: "Get resolved daemon paths",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional working directory override.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Resolved path info",
              ref("PathInfo"),
              examples.pathInfo,
            ),
          },
        },
      },
      "/vcs": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.vcs.get",
          summary: "Get the current Git branch",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Repository root to inspect.",
            },
          ],
          responses: {
            "200": jsonResponse("Branch returned", ref("VcsInfo"), examples.vcsInfo),
          },
        },
      },
      "/command": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.command.list",
          summary: "List slash commands",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Commands returned",
              {
                type: "array",
                items: ref("CommandDescriptor"),
              },
              [examples.command],
            ),
          },
        },
      },
      "/skill": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.skill.list",
          summary: "List skills",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Skills returned",
              {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: true,
                },
              },
              [],
            ),
          },
        },
      },
      "/agent": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.agent.list",
          summary: "List legacy agent presets",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Agent presets returned",
              {
                type: "array",
                items: ref("AgentPreset"),
              },
              [examples.agentPreset],
            ),
          },
        },
      },
      "/provider": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.provider.list",
          summary: "List legacy providers and models",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Providers returned",
              ref("ProviderListResponse"),
              examples.providerList,
            ),
          },
        },
      },
      "/config": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.config.get",
          summary: "Get legacy client config",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional project directory used to resolve the default agent.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Config returned",
              ref("AppConfig"),
              examples.appConfig,
            ),
          },
        },
      },
      "/file": {
        get: {
          tags: ["Filesystem", "Legacy App"],
          operationId: "legacy.file.list",
          summary: "List child files and folders",
          parameters: [
            {
              in: "query",
              name: "path",
              schema: { type: "string" },
              description: "Relative path from `directory`, or absolute path.",
            },
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional root directory. Defaults to the user's home directory.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Directory listing returned",
              {
                type: "array",
                items: ref("FileNode"),
              },
              [examples.fileNode],
            ),
            "404": jsonResponse(
              "Requested path does not exist",
              ref("ErrorResponse"),
              { error: "Requested path was not found." },
            ),
            "500": jsonResponse(
              "Unexpected filesystem error",
              ref("ErrorResponse"),
              errorExamples.internal,
            ),
          },
        },
      },
      "/find/file": {
        get: {
          tags: ["Filesystem", "Legacy App"],
          operationId: "legacy.file.search",
          summary: "Search files or directories breadth-first",
          parameters: [
            {
              in: "query",
              name: "query",
              schema: { type: "string" },
              description: "Case-insensitive filename or absolute-path search term.",
            },
            {
              in: "query",
              name: "type",
              schema: {
                type: "string",
                enum: ["file", "directory"],
              },
              description: "Optional type filter.",
            },
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
            },
            {
              in: "query",
              name: "limit",
              schema: { type: "integer", default: 200 },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Matching absolute paths returned",
              {
                type: "array",
                items: { type: "string" },
              },
              ["/Users/vaibhav/Developer/Personal/mocode/apps"],
            ),
          },
        },
      },
      "/project": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.project.list",
          summary: "List legacy projects",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description:
                "When provided, the daemon resolves or creates a project for that directory and returns it as a single-item list.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Projects returned",
              {
                type: "array",
                items: ref("LegacyProject"),
              },
              [examples.legacyProject],
            ),
          },
        },
      },
      "/project/current": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.project.current",
          summary: "Resolve the current project",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description:
                "Preferred directory. If missing and no projects exist, the daemon returns `404`.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Current project returned",
              ref("LegacyProject"),
              examples.legacyProject,
            ),
            "404": jsonResponse(
              "No project could be resolved",
              ref("ErrorResponse"),
              errorExamples.projectNotFound,
            ),
          },
        },
      },
      "/project/{projectId}": {
        patch: {
          tags: ["Legacy App"],
          operationId: "legacy.project.update",
          summary: "Update a legacy project name",
          parameters: [
            {
              in: "path",
              name: "projectId",
              required: true,
              schema: { type: "string" },
            },
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    name: { type: "string" },
                    icon: {
                      type: "object",
                      additionalProperties: { type: "string" },
                      description: "Accepted for compatibility and ignored today.",
                    },
                  },
                },
                example: {
                  name: "moCODE",
                  icon: {
                    override: "terminal",
                  },
                },
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Project updated",
              ref("LegacyProject"),
              examples.legacyProject,
            ),
            "404": jsonResponse(
              "Project ID was not found",
              ref("ErrorResponse"),
              errorExamples.projectNotFound,
            ),
          },
        },
      },
      "/session": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.list",
          summary: "List legacy sessions",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional project directory filter.",
            },
            {
              in: "query",
              name: "roots",
              schema: { type: "boolean" },
              description: "Accepted by clients but ignored today.",
            },
            {
              in: "query",
              name: "start",
              schema: { type: "integer" },
              description: "Accepted by clients but ignored today.",
            },
            {
              in: "query",
              name: "search",
              schema: { type: "string" },
              description: "Accepted by clients but ignored today.",
            },
            {
              in: "query",
              name: "limit",
              schema: { type: "integer" },
              description: "Accepted by clients but ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Sessions returned",
              {
                type: "array",
                items: ref("LegacySession"),
              },
              [examples.legacySession],
            ),
          },
        },
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.create",
          summary: "Create a legacy session for the resolved project",
          requestBody: {
            required: false,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    parentID: {
                      type: "string",
                      description: "Accepted by clients but ignored today.",
                    },
                    title: {
                      type: "string",
                      description: "Accepted by clients but ignored today.",
                    },
                  },
                },
              },
            },
          },
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description:
                "Project directory. If it does not resolve to a project, the daemon tries to create one.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Session created",
              ref("LegacySession"),
              examples.legacySession,
            ),
            "400": jsonResponse(
              "Project could not be resolved",
              ref("ErrorResponse"),
              errorExamples.projectNotFound,
            ),
            "503": jsonResponse(
              "No agent runtime is available locally",
              ref("ErrorResponse"),
              { error: "No ACP agents are available." },
            ),
            "500": jsonResponse(
              "Session creation failed",
              ref("ErrorResponse"),
              { error: "Unable to create session." },
            ),
          },
        },
      },
      "/session/status": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.status",
          summary: "Get session busy or idle states",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Status map returned",
              ref("LegacySessionStatusMap"),
              examples.sessionStatusMap,
            ),
          },
        },
      },
      "/session/{sessionId}": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.get",
          summary: "Get one legacy session",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Session returned",
              ref("LegacySession"),
              examples.legacySession,
            ),
            "404": jsonResponse(
              "Session ID was not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
          },
        },
        patch: {
          tags: ["Legacy App"],
          operationId: "legacy.session.update",
          summary: "Update a legacy session title",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    title: { type: "string" },
                    archived: {
                      type: "integer",
                      description: "Accepted by clients but ignored today.",
                    },
                  },
                },
                example: {
                  title: "Document the CLI APIs",
                  archived: 0,
                },
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Session updated",
              ref("LegacySession"),
              examples.legacySession,
            ),
            "404": jsonResponse(
              "Session ID was not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
          },
        },
        delete: {
          tags: ["Legacy App"],
          operationId: "legacy.session.delete",
          summary: "Delete a legacy session",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse("Session deleted", ref("BooleanOk"), examples.ok),
            "404": jsonResponse(
              "Session ID was not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
          },
        },
      },
      "/session/{sessionId}/children": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.children",
          summary: "List child sessions",
          description: "Currently returns an empty array.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Child sessions returned",
              {
                type: "array",
                items: ref("LegacySession"),
              },
              [],
            ),
          },
        },
      },
      "/session/{sessionId}/fork": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.fork",
          summary: "Fork a legacy session",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: false,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    messageID: {
                      type: "string",
                      description: "Accepted by clients but ignored today.",
                    },
                  },
                },
              },
            },
          },
          responses: {
            "200": jsonResponse(
              "Forked session returned",
              ref("LegacySession"),
              examples.legacySession,
            ),
            "404": jsonResponse(
              "Session or project not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
            "500": jsonResponse(
              "Unable to fork session",
              ref("ErrorResponse"),
              { error: "Unable to fork session." },
            ),
          },
        },
      },
      "/session/{sessionId}/abort": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.abort",
          summary: "Cancel a running session",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse("Abort accepted", ref("BooleanOk"), examples.ok),
            "404": jsonResponse(
              "Session ID was not found",
              ref("ErrorResponse"),
              errorExamples.sessionNotFound,
            ),
          },
        },
      },
      "/session/{sessionId}/share": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.share",
          summary: "Create a session share link",
          description: "This feature is reserved and currently not implemented.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "Share links are not implemented",
              ref("ErrorResponse"),
              { error: "Session sharing is not implemented yet." },
            ),
          },
        },
        delete: {
          tags: ["Legacy App"],
          operationId: "legacy.session.unshare",
          summary: "Delete a session share link",
          description: "This feature is reserved and currently not implemented.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "Share links are not implemented",
              ref("ErrorResponse"),
              { error: "Session sharing is not implemented yet." },
            ),
          },
        },
      },
      "/session/{sessionId}/summarize": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.summarize",
          summary: "Request session summarization",
          description: "Currently returns success without performing summarization.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: false,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    providerID: { type: "string" },
                    modelID: { type: "string" },
                    auto: { type: "boolean" },
                  },
                },
                example: {
                  providerID: "local",
                  modelID: "codex",
                  auto: false,
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Summarize request accepted", ref("BooleanOk"), examples.ok),
          },
        },
      },
      "/session/{sessionId}/revert": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.revert",
          summary: "Revert a session to a previous message",
          description: "Reserved endpoint. Currently not implemented.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: false,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    messageID: { type: "string" },
                    partID: { type: "string" },
                  },
                },
              },
            },
          },
          responses: {
            "501": jsonResponse(
              "Revert is not implemented",
              ref("ErrorResponse"),
              { error: "Session revert is not implemented yet." },
            ),
          },
        },
      },
      "/session/{sessionId}/unrevert": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.session.unrevert",
          summary: "Undo a prior revert",
          description: "Reserved endpoint. Currently not implemented.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "Revert is not implemented",
              ref("ErrorResponse"),
              { error: "Session revert is not implemented yet." },
            ),
          },
        },
      },
      "/session/{sessionId}/message": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.message.list",
          summary: "List session messages",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
            {
              in: "query",
              name: "limit",
              schema: { type: "integer" },
              description: "Number of most recent messages to return.",
            },
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Accepted for compatibility and ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Messages returned",
              {
                type: "array",
                items: ref("MessageWrapper"),
              },
              [examples.messageWrapper],
            ),
          },
        },
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.message.send",
          summary: "Send a message to a session",
          description:
            "The daemon extracts all `text` parts, joins them with newlines, and queues a background prompt. Model and agent hints are accepted for compatibility but ignored by the current implementation.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("MessageEnvelopeRequest"),
                example: {
                  parts: [
                    {
                      type: "text",
                      text: "Create an OpenAPI document for every CLI HTTP endpoint.",
                    },
                  ],
                  model: {
                    providerID: "local",
                    modelID: "codex",
                  },
                  agent: "Build",
                  variant: "default",
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Prompt queued", ref("BooleanOk"), examples.ok),
            "400": jsonResponse(
              "No text content was provided or JSON could not be parsed",
              ref("ErrorResponse"),
              { error: "Message must contain text." },
            ),
          },
        },
      },
      "/session/{sessionId}/message/{messageId}": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.message.get",
          summary: "Get one message wrapper",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
            {
              in: "path",
              name: "messageId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Message returned",
              ref("MessageWrapper"),
              examples.messageWrapper,
            ),
            "404": jsonResponse(
              "Message ID was not found in the session snapshot",
              ref("ErrorResponse"),
              errorExamples.messageNotFound,
            ),
          },
        },
      },
      "/session/{sessionId}/prompt_async": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.message.sendAsync",
          summary: "Queue an asynchronous prompt",
          description: "Same payload handling and response semantics as `POST /session/{sessionId}/message`.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("MessageEnvelopeRequest"),
                example: {
                  parts: [
                    {
                      type: "text",
                      text: "List every status code that the daemon can return.",
                    },
                  ],
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Prompt queued", ref("BooleanOk"), examples.ok),
            "400": jsonResponse(
              "No text content was provided or JSON could not be parsed",
              ref("ErrorResponse"),
              { error: "Message must contain text." },
            ),
          },
        },
      },
      "/session/{sessionId}/command": {
        post: {
          tags: ["Legacy App"],
          operationId: "legacy.command.send",
          summary: "Send a slash command to a session",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("SessionCommandRequest"),
                example: {
                  command: "run",
                  arguments: "bun run lint",
                  agent: "Build",
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Command queued", ref("BooleanOk"), examples.ok),
            "400": jsonResponse(
              "Missing command or malformed JSON",
              ref("ErrorResponse"),
              { error: "Command is required." },
            ),
          },
        },
      },
      "/permission": {
        get: {
          tags: ["Permissions", "Legacy App"],
          operationId: "legacy.permission.list",
          summary: "List pending permission prompts",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
              description: "Optional directory filter.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Pending permission requests returned",
              {
                type: "array",
                items: ref("PermissionRequest"),
              },
              [examples.permissionRequest],
            ),
          },
        },
      },
      "/permission/{requestId}/reply": {
        post: {
          tags: ["Permissions", "Legacy App"],
          operationId: "legacy.permission.reply",
          summary: "Reply to a pending permission request",
          parameters: [
            {
              in: "path",
              name: "requestId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("PermissionReplyRequest"),
                example: {
                  reply: "allow",
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Reply accepted", ref("BooleanOk"), examples.ok),
            "400": jsonResponse(
              "Reply could not be applied",
              ref("ErrorResponse"),
              { error: "Permission reply failed." },
            ),
            "404": jsonResponse(
              "Permission request ID was not found",
              ref("ErrorResponse"),
              errorExamples.permissionNotFound,
            ),
          },
        },
      },
      "/question": {
        get: {
          tags: ["Permissions", "Legacy App"],
          operationId: "legacy.question.list",
          summary: "List pending structured questions",
          description: "Currently returns an empty array.",
          parameters: [
            {
              in: "query",
              name: "directory",
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "Questions returned",
              {
                type: "array",
                items: ref("QuestionRequest"),
              },
              [],
            ),
          },
        },
      },
      "/question/{requestId}/reply": {
        post: {
          tags: ["Permissions", "Legacy App"],
          operationId: "legacy.question.reply",
          summary: "Reply to a structured question",
          parameters: [
            {
              in: "path",
              name: "requestId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: ref("QuestionReplyRequest"),
                example: {
                  answers: [["Development"]],
                },
              },
            },
          },
          responses: {
            "200": jsonResponse("Reply accepted", ref("BooleanOk"), examples.ok),
          },
        },
      },
      "/question/{requestId}/reject": {
        post: {
          tags: ["Permissions", "Legacy App"],
          operationId: "legacy.question.reject",
          summary: "Reject a structured question",
          parameters: [
            {
              in: "path",
              name: "requestId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse("Rejection accepted", ref("BooleanOk"), examples.ok),
          },
        },
      },
      "/session/{sessionId}/diff": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.diff",
          summary: "Get session file diffs",
          description: "Currently returns an empty array.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
            {
              in: "query",
              name: "messageID",
              schema: { type: "string" },
              description: "Accepted by clients but ignored today.",
            },
          ],
          responses: {
            "200": jsonResponse(
              "Diff list returned",
              {
                type: "array",
                items: ref("FileDiff"),
              },
              [],
            ),
          },
        },
      },
      "/session/{sessionId}/todo": {
        get: {
          tags: ["Legacy App"],
          operationId: "legacy.session.todo",
          summary: "Get session TODO items",
          description: "Currently returns an empty array.",
          parameters: [
            {
              in: "path",
              name: "sessionId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "200": jsonResponse(
              "TODO items returned",
              {
                type: "array",
                items: ref("TodoItem"),
              },
              [],
            ),
          },
        },
      },
      "/pty": {
        get: {
          tags: ["PTY"],
          operationId: "legacy.pty.list",
          summary: "List PTY sessions",
          description: "Currently returns an empty array.",
          responses: {
            "200": jsonResponse(
              "PTY sessions returned",
              {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: true,
                },
              },
              [],
            ),
          },
        },
      },
      "/pty/{ptyId}": {
        get: {
          tags: ["PTY"],
          operationId: "legacy.pty.get",
          summary: "Get a PTY session",
          description: "Placeholder endpoint. PTY passthrough is not implemented yet.",
          parameters: [
            {
              in: "path",
              name: "ptyId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "PTY passthrough not implemented",
              ref("ErrorResponse"),
              errorExamples.notImplemented,
            ),
          },
        },
        patch: {
          tags: ["PTY"],
          operationId: "legacy.pty.update",
          summary: "Update a PTY session",
          description: "Placeholder endpoint. PTY passthrough is not implemented yet.",
          parameters: [
            {
              in: "path",
              name: "ptyId",
              required: true,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            required: false,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    title: { type: "string" },
                    size: {
                      type: "object",
                      properties: {
                        rows: { type: "integer" },
                        cols: { type: "integer" },
                      },
                    },
                  },
                },
              },
            },
          },
          responses: {
            "501": jsonResponse(
              "PTY passthrough not implemented",
              ref("ErrorResponse"),
              errorExamples.notImplemented,
            ),
          },
        },
        delete: {
          tags: ["PTY"],
          operationId: "legacy.pty.delete",
          summary: "Delete a PTY session",
          description: "Placeholder endpoint. PTY passthrough is not implemented yet.",
          parameters: [
            {
              in: "path",
              name: "ptyId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "PTY passthrough not implemented",
              ref("ErrorResponse"),
              errorExamples.notImplemented,
            ),
          },
        },
      },
      "/pty/{ptyId}/connect": {
        get: {
          tags: ["PTY", "Realtime"],
          operationId: "legacy.pty.connect.summary",
          summary: "PTY streaming endpoint placeholder",
          description:
            "Reserved for PTY streaming. The mobile client treats this as a WebSocket URL, but the daemon currently returns `501`.",
          parameters: [
            {
              in: "path",
              name: "ptyId",
              required: true,
              schema: { type: "string" },
            },
          ],
          responses: {
            "501": jsonResponse(
              "PTY streaming not implemented",
              ref("ErrorResponse"),
              errorExamples.notImplemented,
            ),
          },
        },
      },
    },
  };

  const removedLegacyPaths = [
    "/event",
    "/global/health",
    "/command",
    "/agent",
    "/provider",
    "/config",
    "/project",
    "/project/current",
    "/project/{projectId}",
    "/session",
    "/session/status",
    "/session/{sessionId}",
    "/session/{sessionId}/children",
    "/session/{sessionId}/fork",
    "/session/{sessionId}/abort",
    "/session/{sessionId}/share",
    "/session/{sessionId}/summarize",
    "/session/{sessionId}/revert",
    "/session/{sessionId}/unrevert",
    "/session/{sessionId}/message",
    "/session/{sessionId}/message/{messageId}",
    "/session/{sessionId}/prompt_async",
    "/session/{sessionId}/command",
    "/permission",
    "/permission/{requestId}/reply",
    "/question",
    "/question/{requestId}/reply",
    "/question/{requestId}/reject",
    "/session/{sessionId}/diff",
    "/session/{sessionId}/todo",
    "/path",
    "/vcs",
    "/skill",
    "/file",
    "/find/file",
    "/pty",
    "/pty/{ptyId}",
    "/pty/{ptyId}/connect",
  ];

  const helperPathAliases: Record<string, string> = {
    "/path": "/v1/path",
    "/vcs": "/v1/vcs",
    "/skill": "/v1/skills",
    "/file": "/v1/files",
    "/find/file": "/v1/files/search",
    "/pty": "/v1/ptys",
    "/pty/{ptyId}": "/v1/ptys/{ptyId}",
    "/pty/{ptyId}/connect": "/v1/ptys/{ptyId}/connect",
  };

  for (const [from, to] of Object.entries(helperPathAliases)) {
    const source = spec.paths[from];
    if (!source) {
      continue;
    }
    spec.paths[to] = JSON.parse(JSON.stringify(source));
    const pathItem = spec.paths[to];
    for (const operation of Object.values(pathItem)) {
      if (!operation || typeof operation !== "object") {
        continue;
      }
      const op = operation as {
        tags?: string[];
        security?: Array<Record<string, string[]>>;
      };
      if (Array.isArray(op.tags)) {
        op.tags = op.tags.filter((tag) => tag !== "Legacy App");
      }
      op.security = [{ bearerAuth: [] }];
    }
  }

  for (const path of removedLegacyPaths) {
    delete spec.paths[path];
  }

  spec.info.description =
    "HTTP documentation for the local moCODE CLI daemon. This spec covers the structured /v1 ACP client API plus the daemon's remaining filesystem and PTY helper endpoints.";
  spec.tags = spec.tags.filter((tag: { name: string }) => tag.name !== "Legacy App");
  for (const pathItem of Object.values(spec.paths as Record<string, unknown>)) {
    if (!pathItem || typeof pathItem !== "object") {
      continue;
    }
    for (const operation of Object.values(pathItem as Record<string, unknown>)) {
      if (!operation || typeof operation !== "object") {
        continue;
      }
      const op = operation as { tags?: string[] };
      if (Array.isArray(op.tags)) {
        op.tags = op.tags.filter((tag) => tag !== "Legacy App");
      }
    }
  }

  return spec;
}

export function createApiDocsHtml(specPath: string) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>moCODE CLI API Docs</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
    <style>
      :root {
        --bg: #f4efe6;
        --panel: rgba(255, 255, 255, 0.82);
        --ink: #1a2433;
        --muted: #5c6877;
        --line: rgba(26, 36, 51, 0.12);
        --accent: #c1532f;
        --accent-soft: rgba(193, 83, 47, 0.14);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        font-family: "IBM Plex Sans", sans-serif;
        color: var(--ink);
        background:
          radial-gradient(circle at top left, rgba(193, 83, 47, 0.18), transparent 30%),
          radial-gradient(circle at top right, rgba(31, 122, 140, 0.14), transparent 26%),
          linear-gradient(180deg, #fbf8f3 0%, var(--bg) 48%, #efe7dc 100%);
      }

      .hero {
        padding: 32px 24px 20px;
        border-bottom: 1px solid var(--line);
        background:
          linear-gradient(135deg, rgba(255, 255, 255, 0.82), rgba(255, 255, 255, 0.56)),
          repeating-linear-gradient(
            -45deg,
            rgba(26, 36, 51, 0.03) 0,
            rgba(26, 36, 51, 0.03) 2px,
            transparent 2px,
            transparent 12px
          );
        backdrop-filter: blur(18px);
      }

      .hero-inner {
        max-width: 1240px;
        margin: 0 auto;
        display: grid;
        gap: 14px;
      }

      .eyebrow {
        font-family: "IBM Plex Mono", monospace;
        font-size: 12px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--accent);
      }

      h1 {
        margin: 0;
        font-size: clamp(28px, 5vw, 52px);
        line-height: 0.96;
        letter-spacing: -0.04em;
      }

      .lede {
        max-width: 840px;
        margin: 0;
        font-size: 15px;
        line-height: 1.7;
        color: var(--muted);
      }

      .meta {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
      }

      .pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 10px 14px;
        border: 1px solid var(--line);
        border-radius: 999px;
        background: var(--panel);
        color: var(--ink);
        font-size: 13px;
        text-decoration: none;
      }

      .pill strong {
        font-family: "IBM Plex Mono", monospace;
        font-weight: 500;
      }

      #swagger-ui {
        max-width: 1240px;
        margin: 0 auto;
        padding: 18px 18px 42px;
      }

      .swagger-ui .topbar {
        display: none;
      }

      .swagger-ui .scheme-container {
        background: rgba(255, 255, 255, 0.65);
        box-shadow: none;
        border: 1px solid var(--line);
        border-radius: 16px;
        padding: 12px 14px;
      }

      .swagger-ui .opblock {
        border-radius: 16px;
        overflow: hidden;
        border-width: 1px;
      }

      .swagger-ui .opblock .opblock-summary {
        align-items: center;
      }

      .swagger-ui .btn.authorize {
        border-color: var(--accent);
        color: var(--accent);
      }

      .swagger-ui .btn.execute {
        background: var(--accent);
      }

      .swagger-ui .markdown p,
      .swagger-ui .markdown li,
      .swagger-ui .renderedMarkdown p,
      .swagger-ui .renderedMarkdown li {
        font-family: "IBM Plex Sans", sans-serif;
      }

      .swagger-ui code,
      .swagger-ui pre,
      .swagger-ui .microlight {
        font-family: "IBM Plex Mono", monospace;
      }

      @media (max-width: 720px) {
        .hero {
          padding: 24px 16px 16px;
        }

        #swagger-ui {
          padding: 12px 8px 28px;
        }
      }
    </style>
  </head>
  <body>
    <section class="hero">
      <div class="hero-inner">
        <div class="eyebrow">moCODE CLI / OpenAPI 3.0</div>
        <h1>HTTP surface, fully mapped.</h1>
        <p class="lede">
          This page documents the current structured /v1/* ACP client API plus the daemon's remaining filesystem and PTY helper endpoints. WebSocket routes are listed only as upgrade placeholders.
        </p>
        <div class="meta">
          <a class="pill" href="${specPath}"><strong>Raw spec</strong> ${specPath}</a>
          <span class="pill"><strong>Scope</strong> REST + SSE, WebSocket summarized only</span>
          <span class="pill"><strong>Try it out</strong> Enabled against the current daemon origin</span>
        </div>
      </div>
    </section>

    <div id="swagger-ui"></div>

    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: ${JSON.stringify(specPath)},
        dom_id: "#swagger-ui",
        deepLinking: true,
        displayRequestDuration: true,
        docExpansion: "list",
        filter: true,
        persistAuthorization: true,
        tryItOutEnabled: true,
        defaultModelExpandDepth: 2,
        defaultModelsExpandDepth: 1,
        presets: [SwaggerUIBundle.presets.apis],
        layout: "BaseLayout"
      });
    </script>
  </body>
</html>`;
}
