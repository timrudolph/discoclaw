import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export type ServerConfig = {
  port: number;
  host: string;
  dbPath: string;
  workspaceCwd: string;

  // Context modules directory (.context/)
  contextDir: string;

  // Protected special conversations
  generalConversationEnabled: boolean;
  tasksConversationEnabled: boolean;
  journalConversationEnabled: boolean;

  // Auth
  setupToken: string | null;   // required in POST /auth/register body

  // TLS (both must be set to enable HTTPS)
  tlsCert: string | null;      // path to PEM cert file
  tlsKey: string | null;       // path to PEM key file

  // Runtime (mirrors the subset used by the Discord bot)
  claudeBin: string;
  dangerouslySkipPermissions: boolean;
  outputFormat: 'text' | 'stream-json';
  runtimeModel: string;
  runtimeTools: string[];
  runtimeTimeoutMs: number;

  // Appfigures API (optional analytics context injection)
  appfiguresToken: string | null;
  appfiguresClientKey: string | null;
  appfiguresContextPath: string;

  // Feature flags
  beadsEnabled: boolean;

  // Avatar storage directory
  avatarsDir: string;

  // Per-conversation workspace directories
  workspacesBaseDir: string;
};

function str(env: NodeJS.ProcessEnv, key: string, fallback?: string): string {
  const v = env[key]?.trim();
  if (v) return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing required env var: ${key}`);
}

function num(env: NodeJS.ProcessEnv, key: string, fallback: number): number {
  const v = env[key]?.trim();
  if (!v) return fallback;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) throw new Error(`${key} must be a positive number, got "${v}"`);
  return n;
}

function bool(env: NodeJS.ProcessEnv, key: string, fallback: boolean): boolean {
  const v = env[key]?.trim().toLowerCase();
  if (!v) return fallback;
  if (v === '1' || v === 'true') return true;
  if (v === '0' || v === 'false') return false;
  throw new Error(`${key} must be 0/1 or true/false, got "${v}"`);
}

export function parseServerConfig(env: NodeJS.ProcessEnv): ServerConfig {
  const defaultDbPath = path.join(__dirname, '..', '..', 'data', 'server.db');
  const defaultCwd = path.join(__dirname, '..', '..', 'workspace');
  const defaultContextDir = path.join(__dirname, '..', '..', '.context');
  const defaultAppfiguresContextPath = path.join(defaultContextDir, 'appfigures.md');
  const defaultAvatarsDir = path.join(__dirname, '..', '..', 'data', 'avatars');
  const defaultWorkspacesBaseDir = path.join(__dirname, '..', '..', 'data', 'workspaces');
  const rawTools = env.RUNTIME_TOOLS?.trim();
  const runtimeTools = rawTools
    ? rawTools.split(/[,\s]+/).map((t) => t.trim()).filter(Boolean)
    : ['Bash', 'Read', 'Write', 'Edit', 'Glob', 'Grep', 'WebSearch', 'WebFetch'];

  const outputFormatRaw = env.CLAUDE_OUTPUT_FORMAT?.trim();
  if (outputFormatRaw && outputFormatRaw !== 'text' && outputFormatRaw !== 'stream-json') {
    throw new Error(`CLAUDE_OUTPUT_FORMAT must be "text" or "stream-json", got "${outputFormatRaw}"`);
  }

  const tlsCert = env.TLS_CERT?.trim() || null;
  const tlsKey = env.TLS_KEY?.trim() || null;
  if ((tlsCert && !tlsKey) || (!tlsCert && tlsKey)) {
    throw new Error('TLS_CERT and TLS_KEY must both be set (or both omitted)');
  }

  return {
    generalConversationEnabled: bool(env, 'SERVER_GENERAL_CONVERSATION', false),
    tasksConversationEnabled: bool(env, 'SERVER_TASKS_CONVERSATION', false),
    journalConversationEnabled: bool(env, 'SERVER_JOURNAL_CONVERSATION', false),
    port: num(env, 'SERVER_PORT', 4242),
    host: str(env, 'SERVER_HOST', '127.0.0.1'),
    dbPath: str(env, 'SERVER_DB_PATH', defaultDbPath),
    workspaceCwd: str(env, 'WORKSPACE_CWD', defaultCwd),
    contextDir: str(env, 'SERVER_CONTEXT_DIR', defaultContextDir),
    setupToken: env.SETUP_TOKEN?.trim() || null,
    tlsCert,
    tlsKey,
    claudeBin: str(env, 'CLAUDE_BIN', 'claude'),
    dangerouslySkipPermissions: bool(env, 'CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS', false),
    outputFormat: (outputFormatRaw as 'text' | 'stream-json') ?? 'stream-json',
    runtimeModel: str(env, 'RUNTIME_MODEL', 'opus'),
    runtimeTools,
    runtimeTimeoutMs: num(env, 'RUNTIME_TIMEOUT_MS', 10 * 60_000),
    appfiguresToken: env.APPFIGURES_TOKEN?.trim() || null,
    appfiguresClientKey: env.APPFIGURES_CLIENT_KEY?.trim() || null,
    appfiguresContextPath: str(env, 'SERVER_APPFIGURES_CONTEXT', defaultAppfiguresContextPath),
    beadsEnabled: bool(env, 'SERVER_BEADS_ENABLED', true),
    avatarsDir: str(env, 'SERVER_AVATARS_DIR', defaultAvatarsDir),
    workspacesBaseDir: str(env, 'SERVER_WORKSPACES_DIR', defaultWorkspacesBaseDir),
  };
}
