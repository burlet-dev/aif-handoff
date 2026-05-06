import { existsSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { spawnDev } from "./lib/spawn-dev.mjs";
import { assertWorkspacePackagesResolveToSource } from "./lib/workspace-resolution-guard.mjs";

// Minimum Node version required transitively (Vite 8). Keep in sync with
// `engines.node` in the root package.json.
const REQUIRED_NODE_MAJOR = 20;
const REQUIRED_NODE_MINOR_FOR_20 = 19;

function assertNodeVersion() {
  const [maj, min] = process.versions.node.split(".").map(Number);
  const ok =
    (maj === REQUIRED_NODE_MAJOR && min >= REQUIRED_NODE_MINOR_FOR_20) || maj > REQUIRED_NODE_MAJOR;
  if (!ok) {
    console.error(
      `[dev] Node ${process.versions.node} is not supported. Requires Node ${REQUIRED_NODE_MAJOR}.${REQUIRED_NODE_MINOR_FOR_20}+ or newer (Vite 8 dependency).\n` +
        `[dev] Use nvm: \`nvm use\` (see .nvmrc) or install a compatible version.`,
    );
    process.exit(1);
  }
}

// `better-sqlite3` is a native module. After switching the Node version, the
// prebuilt binary may target a different `NODE_MODULE_VERSION`, which makes
// the API crash with ERR_DLOPEN_FAILED. `node --watch` swallows that crash
// and keeps the process alive silently, so the user only sees a "Bad
// Gateway" from the Vite proxy. Run an explicit preflight to turn this
// silent failure into an actionable error before Turbo starts.
function assertNativeModulesUsable() {
  const require = createRequire(import.meta.url);
  try {
    require("better-sqlite3");
  } catch (err) {
    if (err && err.code === "ERR_DLOPEN_FAILED") {
      console.error(
        `[dev] better-sqlite3 native binary is incompatible with the current Node (${process.version}).\n` +
          `[dev] Run: \`npm rebuild better-sqlite3\` and retry \`npm run dev\`.\n` +
          `[dev] Original error: ${err.message}`,
      );
      process.exit(1);
    }
    // Re-throw other errors as-is so Turbo/Node can surface the stack trace.
    throw err;
  }
}

// Minimal root .env loader for local dev scripts. Supports single-line KEY=VALUE pairs only.
// (helpers below: assertNodeVersion / assertNativeModulesUsable run before Turbo to fail fast)
function parseEnvFile(path) {
  const entries = {};
  const lines = readFileSync(path, "utf8").split(/\r?\n/u);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const normalized = trimmed.startsWith("export ") ? trimmed.slice(7) : trimmed;
    const separatorIndex = normalized.indexOf("=");
    if (separatorIndex < 0) continue;

    const key = normalized.slice(0, separatorIndex).trim();
    if (!key) continue;

    let value = normalized.slice(separatorIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    entries[key] = value;
  }

  return entries;
}

function loadRootEnv() {
  const resolvedEnv = {};

  for (const filename of [".env", ".env.local"]) {
    const path = resolve(process.cwd(), filename);
    if (!existsSync(path)) continue;
    Object.assign(resolvedEnv, parseEnvFile(path));
  }

  for (const [key, value] of Object.entries(resolvedEnv)) {
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

// MCP HTTP is optional in the root dev launcher, so invalid values disable the
// extra HTTP process instead of aborting the whole dev stack.
function resolveMcpPort(value) {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }

  const port = Number(trimmed);
  return Number.isInteger(port) && port > 0 && port <= 65535 ? String(port) : null;
}

loadRootEnv();
assertNodeVersion();
assertNativeModulesUsable();
assertWorkspacePackagesResolveToSource();

const filters = ["@aif/api", "@aif/web", "@aif/agent"];
const mcpPort = resolveMcpPort(process.env.MCP_PORT);

if (mcpPort) {
  process.env.MCP_PORT = mcpPort;
  filters.push("@aif/mcp");
  console.log(`[dev] MCP enabled on port ${mcpPort}`);
}

const args = [
  "turbo",
  "run",
  "dev",
  ...filters.flatMap((filter) => ["--filter", filter]),
  ...process.argv.slice(2),
];

spawnDev({
  command: "npx",
  args,
  env: process.env,
  label: "dev",
});
