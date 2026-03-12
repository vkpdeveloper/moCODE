import { mkdirSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { join } from "node:path";

import type { StatePaths } from "./types";

function ensureDir(path: string) {
  mkdirSync(path, { recursive: true });
}

function resolveLinuxStateHome() {
  return process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
}

function resolveLinuxConfigHome() {
  return process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
}

function resolveLinuxCacheHome() {
  return process.env.XDG_CACHE_HOME || join(homedir(), ".cache");
}

export function getStatePaths(): StatePaths {
  let stateDir: string;
  let cacheDir: string;
  let configDir: string;
  let logDir: string;
  const managedHomeDir = join(homedir(), ".mocode");
  const managedBinDir = join(managedHomeDir, "bin");
  const managedAgentsDir = join(managedHomeDir, "agents");

  switch (process.platform) {
    case "darwin": {
      const base = join(homedir(), "Library", "Application Support", "moCODE");
      stateDir = join(base, "cli");
      configDir = join(homedir(), "Library", "Preferences", "moCODE");
      cacheDir = join(homedir(), "Library", "Caches", "moCODE");
      logDir = join(homedir(), "Library", "Logs", "moCODE");
      break;
    }
    case "win32": {
      const localAppData =
        process.env.LOCALAPPDATA || join(homedir(), "AppData", "Local");
      const roamingAppData =
        process.env.APPDATA || join(homedir(), "AppData", "Roaming");
      stateDir = join(localAppData, "moCODE");
      cacheDir = join(localAppData, "moCODE", "cache");
      configDir = join(roamingAppData, "moCODE");
      logDir = join(localAppData, "moCODE", "logs");
      break;
    }
    default: {
      stateDir = join(resolveLinuxStateHome(), "mocode");
      cacheDir = join(resolveLinuxCacheHome(), "mocode");
      configDir = join(resolveLinuxConfigHome(), "mocode");
      logDir = join(stateDir, "logs");
      break;
    }
  }

  const paths = {
    stateDir,
    cacheDir,
    configDir,
    logDir,
    managedHomeDir,
    managedBinDir,
    managedAgentsDir,
    managedAgentsManifestPath: join(managedHomeDir, "agents.json"),
    databasePath: join(stateDir, "state.db"),
  };

  ensureDir(paths.stateDir);
  ensureDir(paths.cacheDir);
  ensureDir(paths.configDir);
  ensureDir(paths.logDir);
  ensureDir(paths.managedHomeDir);
  ensureDir(paths.managedBinDir);
  ensureDir(paths.managedAgentsDir);

  return paths;
}

export function getDefaultDeviceName() {
  return hostname();
}
