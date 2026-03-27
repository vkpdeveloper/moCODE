import { randomUUID, createHash } from "node:crypto";
import { basename, resolve } from "node:path";

import { Database } from "bun:sqlite";

import type {
  AgentDescriptor,
  AgentRecord,
  JsonValue,
  PairedDeviceRecord,
  ProjectRecord,
  SessionEntryRecord,
  SessionEntrySnapshot,
  SessionRecord,
  SessionSnapshot,
} from "./types";

type SqliteRow = Record<string, string | number | null>;

function nowIso() {
  return new Date().toISOString();
}

function parseRecord<T>(row: SqliteRow | null | undefined, transform: (row: SqliteRow) => T): T | null {
  if (!row) {
    return null;
  }
  return transform(row);
}

function toProject(row: SqliteRow): ProjectRecord {
  return {
    id: String(row.id),
    rootPath: String(row.root_path),
    detectedName: String(row.detected_name),
    displayName: row.display_name === null ? null : String(row.display_name),
    preferredAgentId:
      row.preferred_agent_id === null ? null : String(row.preferred_agent_id),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at),
    lastOpenedAt:
      row.last_opened_at === null ? null : String(row.last_opened_at),
  };
}

function toSession(row: SqliteRow): SessionRecord {
  return {
    id: String(row.id),
    projectId: String(row.project_id),
    agentId: String(row.agent_id),
    agentSessionId: String(row.agent_session_id),
    cwd: String(row.cwd),
    title: row.title === null ? null : String(row.title),
    status: String(row.status),
    controllerDeviceId:
      row.controller_device_id === null
        ? null
        : String(row.controller_device_id),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at),
    lastStopReason:
      row.last_stop_reason === null ? null : String(row.last_stop_reason),
    capabilitiesJson:
      row.capabilities_json === null ? null : String(row.capabilities_json),
  };
}

function toEntry(row: SqliteRow): SessionEntryRecord {
  return {
    id: String(row.id),
    sessionId: String(row.session_id),
    seq: Number(row.seq),
    kind: String(row.kind),
    payloadJson: String(row.payload_json),
    createdAt: String(row.created_at),
  };
}

function toAgent(row: SqliteRow): AgentRecord {
  return {
    id: String(row.id),
    kind: String(row.kind),
    source: String(row.source),
    installState: String(row.install_state),
    version: row.version === null ? null : String(row.version),
    binaryPath: row.binary_path === null ? null : String(row.binary_path),
    metadataJson:
      row.metadata_json === null ? null : String(row.metadata_json),
    updatedAt: String(row.updated_at),
  };
}

function toPairedDevice(row: SqliteRow): PairedDeviceRecord {
  return {
    id: String(row.id),
    name: String(row.name),
    tokenHash: String(row.token_hash),
    createdAt: String(row.created_at),
    lastSeenAt: row.last_seen_at === null ? null : String(row.last_seen_at),
    revokedAt: row.revoked_at === null ? null : String(row.revoked_at),
  };
}

export class StateDatabase {
  readonly sqlite: Database;

  constructor(path: string) {
    this.sqlite = new Database(path);
    this.sqlite.exec("PRAGMA journal_mode = WAL;");
    this.sqlite.exec("PRAGMA foreign_keys = ON;");
    this.initialize();
  }

  initialize() {
    this.sqlite.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        root_path TEXT NOT NULL UNIQUE,
        detected_name TEXT NOT NULL,
        display_name TEXT,
        preferred_agent_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_opened_at TEXT
      );

      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        agent_id TEXT NOT NULL,
        agent_session_id TEXT NOT NULL,
        cwd TEXT NOT NULL,
        title TEXT,
        status TEXT NOT NULL,
        controller_device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_stop_reason TEXT,
        capabilities_json TEXT,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_sessions_project_id ON sessions(project_id);
      CREATE INDEX IF NOT EXISTS idx_sessions_agent_session_id ON sessions(agent_session_id);

      CREATE TABLE IF NOT EXISTS session_entries (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        UNIQUE(session_id, seq)
      );

      CREATE INDEX IF NOT EXISTS idx_session_entries_session_id_seq
      ON session_entries(session_id, seq);

      CREATE TABLE IF NOT EXISTS paired_devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        last_seen_at TEXT,
        revoked_at TEXT
      );

      CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        source TEXT NOT NULL,
        install_state TEXT NOT NULL,
        version TEXT,
        binary_path TEXT,
        metadata_json TEXT,
        updated_at TEXT NOT NULL
      );
    `);
  }

  close() {
    this.sqlite.close();
  }

  listProjects(): ProjectRecord[] {
    const rows = this.sqlite
      .query("SELECT * FROM projects ORDER BY COALESCE(last_opened_at, updated_at) DESC")
      .all() as SqliteRow[];
    return rows.map(toProject);
  }

  searchProjects(query: string): ProjectRecord[] {
    const normalized = `%${query.trim().toLowerCase()}%`;
    const rows = this.sqlite
      .query(
        `
        SELECT * FROM projects
        WHERE LOWER(root_path) LIKE ?1
           OR LOWER(detected_name) LIKE ?1
           OR LOWER(COALESCE(display_name, '')) LIKE ?1
        ORDER BY COALESCE(last_opened_at, updated_at) DESC
      `,
      )
      .all(normalized) as SqliteRow[];
    return rows.map(toProject);
  }

  getProject(id: string): ProjectRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM projects WHERE id = ?1")
      .get(id) as SqliteRow | null;
    return parseRecord(row, toProject);
  }

  getProjectByRootPath(rootPath: string): ProjectRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM projects WHERE root_path = ?1")
      .get(resolve(rootPath)) as SqliteRow | null;
    return parseRecord(row, toProject);
  }

  openProject(rootPath: string): ProjectRecord {
    const normalizedPath = resolve(rootPath);
    const current = this.getProjectByRootPath(normalizedPath);
    const timestamp = nowIso();

    if (current) {
      this.sqlite
        .query(
          `
          UPDATE projects
          SET updated_at = ?2, last_opened_at = ?2
          WHERE id = ?1
        `,
        )
        .run(current.id, timestamp);
      return this.getProject(current.id) as ProjectRecord;
    }

    const id = randomUUID();
    const detectedName = basename(normalizedPath);
    this.sqlite
      .query(
        `
        INSERT INTO projects (
          id, root_path, detected_name, display_name, preferred_agent_id,
          created_at, updated_at, last_opened_at
        ) VALUES (?1, ?2, ?3, NULL, NULL, ?4, ?4, ?4)
      `,
      )
      .run(id, normalizedPath, detectedName, timestamp);

    return this.getProject(id) as ProjectRecord;
  }

  updateProject(
    id: string,
    updates: { displayName?: string | null; preferredAgentId?: string | null },
  ): ProjectRecord | null {
    const current = this.getProject(id);
    if (!current) {
      return null;
    }
    const timestamp = nowIso();
    this.sqlite
      .query(
        `
        UPDATE projects
        SET display_name = ?2,
            preferred_agent_id = ?3,
            updated_at = ?4
        WHERE id = ?1
      `,
      )
      .run(
        id,
        updates.displayName === undefined ? current.displayName : updates.displayName,
        updates.preferredAgentId === undefined
          ? current.preferredAgentId
          : updates.preferredAgentId,
        timestamp,
      );
    return this.getProject(id);
  }

  listSessions(projectId?: string): SessionRecord[] {
    const rows = projectId
      ? ((this.sqlite
          .query(
            "SELECT * FROM sessions WHERE project_id = ?1 ORDER BY updated_at DESC",
          )
          .all(projectId) as SqliteRow[]) ?? [])
      : ((this.sqlite
          .query("SELECT * FROM sessions ORDER BY updated_at DESC")
          .all() as SqliteRow[]) ?? []);
    return rows.map(toSession);
  }

  getSession(id: string): SessionRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM sessions WHERE id = ?1")
      .get(id) as SqliteRow | null;
    return parseRecord(row, toSession);
  }

  deleteSession(id: string) {
    const result = this.sqlite
      .query("DELETE FROM sessions WHERE id = ?1")
      .run(id);
    return result.changes > 0;
  }

  getSessionByAgentSession(agentSessionId: string): SessionRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM sessions WHERE agent_session_id = ?1 ORDER BY updated_at DESC LIMIT 1")
      .get(agentSessionId) as SqliteRow | null;
    return parseRecord(row, toSession);
  }

  getSessionByAgentSessionForAgent(
    agentId: string,
    agentSessionId: string,
  ): SessionRecord | null {
    const row = this.sqlite
      .query(
        `
        SELECT * FROM sessions
        WHERE agent_id = ?1 AND agent_session_id = ?2
        ORDER BY updated_at DESC
        LIMIT 1
      `,
      )
      .get(agentId, agentSessionId) as SqliteRow | null;
    return parseRecord(row, toSession);
  }

  createSession(input: {
    projectId: string;
    agentId: string;
    agentSessionId: string;
    cwd: string;
    title?: string | null;
    status: string;
    controllerDeviceId?: string | null;
    capabilities?: JsonValue;
  }): SessionRecord {
    const id = randomUUID();
    const timestamp = nowIso();
    this.sqlite
      .query(
        `
        INSERT INTO sessions (
          id, project_id, agent_id, agent_session_id, cwd, title, status,
          controller_device_id, created_at, updated_at, last_stop_reason, capabilities_json
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9, NULL, ?10)
      `,
      )
      .run(
        id,
        input.projectId,
        input.agentId,
        input.agentSessionId,
        resolve(input.cwd),
        input.title ?? null,
        input.status,
        input.controllerDeviceId ?? null,
        timestamp,
        input.capabilities === undefined ? null : JSON.stringify(input.capabilities),
      );
    return this.getSession(id) as SessionRecord;
  }

  updateSession(
    id: string,
    updates: {
      projectId?: string;
      agentSessionId?: string;
      cwd?: string;
      title?: string | null;
      status?: string;
      controllerDeviceId?: string | null;
      lastStopReason?: string | null;
      capabilities?: JsonValue | null;
    },
  ): SessionRecord | null {
    const current = this.getSession(id);
    if (!current) {
      return null;
    }
    const timestamp = nowIso();
    this.sqlite
      .query(
        `
        UPDATE sessions
        SET project_id = ?2,
            agent_session_id = ?3,
            cwd = ?4,
            title = ?5,
            status = ?6,
            controller_device_id = ?7,
            updated_at = ?8,
            last_stop_reason = ?9,
            capabilities_json = ?10
        WHERE id = ?1
      `,
      )
      .run(
        id,
        updates.projectId ?? current.projectId,
        updates.agentSessionId ?? current.agentSessionId,
        updates.cwd === undefined ? current.cwd : resolve(updates.cwd),
        updates.title === undefined ? current.title : updates.title,
        updates.status ?? current.status,
        updates.controllerDeviceId === undefined
          ? current.controllerDeviceId
          : updates.controllerDeviceId,
        timestamp,
        updates.lastStopReason === undefined
          ? current.lastStopReason
          : updates.lastStopReason,
        updates.capabilities === undefined
          ? current.capabilitiesJson
          : updates.capabilities === null
            ? null
            : JSON.stringify(updates.capabilities),
      );
    return this.getSession(id);
  }

  upsertSessionFromAgent(input: {
    projectId: string;
    agentId: string;
    agentSessionId: string;
    cwd: string;
    title?: string | null;
    status?: string;
    capabilities?: JsonValue | null;
  }): SessionRecord {
    const existing = this.getSessionByAgentSessionForAgent(
      input.agentId,
      input.agentSessionId,
    );
    if (existing) {
      return this.updateSession(existing.id, {
        projectId: input.projectId,
        cwd: input.cwd,
        title: input.title,
        status: input.status ?? existing.status,
        capabilities: input.capabilities,
      }) as SessionRecord;
    }

    return this.createSession({
      projectId: input.projectId,
      agentId: input.agentId,
      agentSessionId: input.agentSessionId,
      cwd: input.cwd,
      title: input.title,
      status: input.status ?? "idle",
      capabilities: input.capabilities ?? undefined,
    });
  }

  listSessionEntries(sessionId: string): SessionEntryRecord[] {
    const rows = this.sqlite
      .query(
        "SELECT * FROM session_entries WHERE session_id = ?1 ORDER BY seq ASC",
      )
      .all(sessionId) as SqliteRow[];
    return rows.map(toEntry);
  }

  appendSessionEntry(
    sessionId: string,
    kind: string,
    payload: JsonValue,
  ): SessionEntrySnapshot {
    const insert = this.sqlite.transaction(
      (
        currentSessionId: string,
        currentKind: string,
        currentPayload: JsonValue,
      ) => {
      const row = this.sqlite
        .query(
          "SELECT COALESCE(MAX(seq), 0) as seq FROM session_entries WHERE session_id = ?1",
        )
        .get(currentSessionId) as SqliteRow | null;
      const seq = Number(row?.seq ?? 0) + 1;
      const id = randomUUID();
      const createdAt = nowIso();

      this.sqlite
        .query(
          `
          INSERT INTO session_entries (id, session_id, seq, kind, payload_json, created_at)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        `,
        )
        .run(id, currentSessionId, seq, currentKind, JSON.stringify(currentPayload), createdAt);

      this.sqlite
        .query("UPDATE sessions SET updated_at = ?2 WHERE id = ?1")
        .run(currentSessionId, createdAt);
      return {
        id,
        seq,
        kind: currentKind,
        payload: currentPayload,
        createdAt,
      } satisfies SessionEntrySnapshot;
    });

    return insert(sessionId, kind, payload);
  }

  getSessionSnapshot(id: string): SessionSnapshot | null {
    const session = this.getSession(id);
    if (!session) {
      return null;
    }
    const entries = this.listSessionEntries(id).map((entry) => ({
      id: entry.id,
      seq: entry.seq,
      kind: entry.kind,
      payload: JSON.parse(entry.payloadJson) as JsonValue,
      createdAt: entry.createdAt,
    }));
    return { session, entries };
  }

  upsertAgent(descriptor: AgentDescriptor): AgentRecord {
    const timestamp = nowIso();
    this.sqlite
      .query(
        `
        INSERT INTO agents (id, kind, source, install_state, version, binary_path, metadata_json, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        ON CONFLICT(id) DO UPDATE SET
          kind = excluded.kind,
          source = excluded.source,
          install_state = excluded.install_state,
          version = excluded.version,
          binary_path = excluded.binary_path,
          metadata_json = excluded.metadata_json,
          updated_at = excluded.updated_at
      `,
      )
      .run(
        descriptor.id,
        descriptor.kind,
        descriptor.source,
        descriptor.installState,
        descriptor.version,
        descriptor.binaryPath,
        JSON.stringify(descriptor.metadata),
        timestamp,
      );

    return this.getAgent(descriptor.id) as AgentRecord;
  }

  listAgents(): AgentRecord[] {
    const rows = this.sqlite
      .query("SELECT * FROM agents ORDER BY id ASC")
      .all() as SqliteRow[];
    return rows.map(toAgent);
  }

  getAgent(id: string): AgentRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM agents WHERE id = ?1")
      .get(id) as SqliteRow | null;
    return parseRecord(row, toAgent);
  }

  deleteAgent(id: string) {
    const result = this.sqlite
      .query("DELETE FROM agents WHERE id = ?1")
      .run(id);
    return result.changes > 0;
  }

  createPairedDevice(name: string, rawToken: string): { device: PairedDeviceRecord; token: string } {
    const id = randomUUID();
    const timestamp = nowIso();
    const tokenHash = this.hashToken(rawToken);
    this.sqlite
      .query(
        `
        INSERT INTO paired_devices (id, name, token_hash, created_at, last_seen_at, revoked_at)
        VALUES (?1, ?2, ?3, ?4, ?4, NULL)
      `,
      )
      .run(id, name, tokenHash, timestamp);

    return {
      device: this.getPairedDeviceById(id) as PairedDeviceRecord,
      token: rawToken,
    };
  }

  hashToken(token: string) {
    return createHash("sha256").update(token).digest("hex");
  }

  getPairedDeviceByToken(token: string): PairedDeviceRecord | null {
    const row = this.sqlite
      .query(
        `
        SELECT * FROM paired_devices
        WHERE token_hash = ?1 AND revoked_at IS NULL
        LIMIT 1
      `,
      )
      .get(this.hashToken(token)) as SqliteRow | null;
    return parseRecord(row, toPairedDevice);
  }

  getPairedDeviceById(id: string): PairedDeviceRecord | null {
    const row = this.sqlite
      .query("SELECT * FROM paired_devices WHERE id = ?1")
      .get(id) as SqliteRow | null;
    return parseRecord(row, toPairedDevice);
  }

  touchPairedDevice(id: string) {
    this.sqlite
      .query("UPDATE paired_devices SET last_seen_at = ?2 WHERE id = ?1")
      .run(id, nowIso());
  }
}
