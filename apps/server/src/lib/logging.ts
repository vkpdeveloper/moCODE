function isVerboseFlag(value: string) {
  return value === "--verbose" || value === "-v";
}

export function isVerboseLoggingEnabled() {
  return process.argv.some(isVerboseFlag);
}

export function logInfo(...args: unknown[]) {
  if (!isVerboseLoggingEnabled()) {
    return;
  }

  console.log(...args);
}

export function logError(...args: unknown[]) {
  if (!isVerboseLoggingEnabled()) {
    return;
  }

  console.error(...args);
}
