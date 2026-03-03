import { readText, writeText } from "../utils/fs"
import { joinPath, resolvePath } from "../utils/path"
import { saveLastChannel } from "../utils/last-channel"

type EnvMap = Record<string, string>

// @ts-ignore - Bun-specific import.meta.dir
const REPO_ROOT = resolvePath(import.meta.dir, "..", "..")
const ENV_FILE = resolvePath(REPO_ROOT, ".env")

function ask(promptText: string): string {
  const value = prompt(promptText)
  return (value ?? "").trim()
}

function parseEnv(lines: string[]): EnvMap {
  const out: EnvMap = {}
  for (const line of lines) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const idx = trimmed.indexOf("=")
    if (idx <= 0) continue
    const key = trimmed.slice(0, idx).trim()
    const value = trimmed.slice(idx + 1)
    out[key] = value
  }
  return out
}

function updateEnvLines(lines: string[], updates: EnvMap): string[] {
  const out = [...lines]
  const seen = new Set<string>()
  for (let i = 0; i < out.length; i += 1) {
    const line = out[i]
    const idx = line.indexOf("=")
    if (idx <= 0) continue
    const key = line.slice(0, idx).trim()
    if (Object.prototype.hasOwnProperty.call(updates, key)) {
      out[i] = `${key}=${updates[key]}`
      seen.add(key)
    }
  }
  for (const [key, value] of Object.entries(updates)) {
    if (!seen.has(key)) out.push(`${key}=${value}`)
  }
  return out
}

async function loadEnvFile(): Promise<string[]> {
  try {
    const raw = await readText(ENV_FILE)
    return raw.split(/\r?\n/)
  } catch {
    return []
  }
}

async function saveEnvFile(lines: string[]): Promise<void> {
  await writeText(ENV_FILE, lines.join("\n").trimEnd() + "\n")
}

async function resolveModel(): Promise<string> {
  const modelFromEnv = Bun.env.OPENCODE_MODEL?.trim()
  if (modelFromEnv) return modelFromEnv

  const home = Bun.env.HOME ?? ""
  const stateHome = Bun.env.XDG_STATE_HOME ?? `${home}/.local/state`
  const modelFile = joinPath(stateHome, "opencode", "model.json")
  try {
    const raw = await readText(modelFile)
    const parsed = JSON.parse(raw) as { recent?: Array<{ providerID?: string; modelID?: string }> }
    const first = parsed.recent?.[0]
    if (first?.providerID && first?.modelID) return `${first.providerID}/${first.modelID}`
  } catch {
    // ignore
  }
  return ""
}

async function ensureOpencodeAuth(): Promise<void> {
  const model = await resolveModel()
  if (model) return

  console.log("OpenCode model not found. Launching 'opencode' for setup...")
  const proc = Bun.spawn(["opencode", "auth", "login"], { stdin: "inherit", stdout: "inherit", stderr: "inherit" })
  await proc.exited

  const next = await resolveModel()
  if (!next) {
    console.log("Model not found. Use '/models' inside the OpenCode TUI to pick a model.")
    await Bun.sleep(3_000)
    const tui = Bun.spawn(["opencode"], { stdin: "inherit", stdout: "inherit", stderr: "inherit" })
    await tui.exited
  }
}

async function main(): Promise<void> {
  const lines = await loadEnvFile()
  const current = parseEnv(lines)
  const updates: EnvMap = {}

  const enableTelegram = ask("Enable Telegram? (y/N): ")
  if (enableTelegram.toLowerCase().startsWith("y")) {
    const token = ask("Telegram bot token: ")
    const telegramUserID = ask("Telegram user ID (optional): ")
    updates.ENABLE_TELEGRAM = "true"
    if (token) updates.TELEGRAM_BOT_TOKEN = token
    if (telegramUserID) {
      await saveLastChannel(telegramUserID)
    }
  } else {
    updates.ENABLE_TELEGRAM = "false"
  }

  console.log("WHITELIST_PAIR_TOKEN allows users to self-pair via '/pair <token>' in chat.")
  const pairTokenPrompt = current.WHITELIST_PAIR_TOKEN
    ? "Whitelist pair token (leave blank to keep current): "
    : "Whitelist pair token (leave blank to disable): "
  const pairToken = ask(pairTokenPrompt)
  if (pairToken) updates.WHITELIST_PAIR_TOKEN = pairToken

  if (updates.ENABLE_TELEGRAM !== "true") {
    console.log("Telegram not enabled. Aborting setup.")
    process.exit(1)
  }

  const merged = updateEnvLines(lines, updates)
  await saveEnvFile(merged)

  await ensureOpencodeAuth()
  
  console.log("")
  console.log("============================================")
  console.log("Setup complete!")
  console.log("")
  console.log("Quick commands:")
  console.log("  octoflow start     - Start the bot")
  console.log("  octoflow dev       - Start with auto-reload")
  console.log("  octoflow status    - Check if running")
  console.log("")
  console.log("To install as a service (auto-start on boot):")
  console.log("  octoflow install-service")
  console.log("============================================")
  
  process.exit(0)
}

void main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error))
  process.exit(1)
})
