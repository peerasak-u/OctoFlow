#!/usr/bin/env bun
import { execSync } from "child_process"

// Get absolute path without .. using Bun's file URL API
// @ts-ignore - Bun-specific import.meta.dir
const REPO_ROOT = new URL("../..", import.meta.url).pathname.replace(/\/$/, "")
const PID_FILE = `${REPO_ROOT}/.data/octoflow.pid`

function showHelp() {
  console.log(`
OctoFlow CLI

Usage: octoflow <command>

Commands:
  start              Start OctoFlow bot (foreground mode)
  stop               Stop running OctoFlow bot
  restart            Restart the bot
  status             Check if bot is running
  logs               View recent logs
  setup              Run interactive setup wizard
  dev                Start in development mode (with auto-reload)
  install-service    Install as system service (auto-start on boot)
  service            Manage system service (start/stop/restart/status)

Examples:
  octoflow start              # Start the bot
  octoflow service start      # Start system service
  octoflow service stop       # Stop system service
  octoflow logs               # View logs
  octoflow setup              # Configure tokens and settings
`)
}

function showServiceHelp() {
  console.log(`
OctoFlow Service Manager

Usage: octoflow service <command>

Commands:
  start       Start the system service
  stop        Stop the system service
  restart     Restart the system service
  status      Check system service status

Examples:
  octoflow service start    # Start service
  octoflow service stop     # Stop service
  octoflow service status   # Check if service is running
`)
}

async function isRunning(): Promise<boolean> {
  try {
    const pid = await Bun.file(PID_FILE).text()
    if (!pid) return false
    // Check if process exists (Unix signal 0)
    process.kill(parseInt(pid.trim()), 0)
    return true
  } catch {
    return false
  }
}

async function start() {
  if (await isRunning()) {
    console.log("⚠️  OctoFlow is already running")
    console.log("   Run 'octoflow logs' to see output")
    return
  }

  console.log("🚀 Starting OctoFlow...")
  console.log("   Press Ctrl+C to stop")
  console.log("")

  // Run the main app
  const proc = Bun.spawn({
    cmd: ["bun", "src/index.ts"],
    cwd: REPO_ROOT,
    stdio: ["inherit", "inherit", "inherit"],
    env: {
      ...process.env,
      OPENCODE_CONFIG_DIR: REPO_ROOT,
    },
  })

  // Save PID
  await Bun.write(PID_FILE, proc.pid.toString())

  // Wait for process
  await proc.exited
  
  // Clean up PID file
  try {
    await Bun.file(PID_FILE).delete()
  } catch {}
}

async function dev() {
  console.log("🚀 Starting OctoFlow in dev mode (auto-reload)...")
  console.log("   Press Ctrl+C to stop")
  console.log("")

  const proc = Bun.spawn({
    cmd: ["bun", "--watch", "src/index.ts"],
    cwd: REPO_ROOT,
    stdio: ["inherit", "inherit", "inherit"],
    env: {
      ...process.env,
      OPENCODE_CONFIG_DIR: REPO_ROOT,
    },
  })

  await proc.exited
}

async function stop() {
  if (!(await isRunning())) {
    console.log("✓ OctoFlow is not running")
    return
  }

  try {
    const pid = await Bun.file(PID_FILE).text()
    process.kill(parseInt(pid.trim()), "SIGTERM")
    console.log("✓ OctoFlow stopped")
    
    try {
      await Bun.file(PID_FILE).delete()
    } catch {}
  } catch (error) {
    console.error("✗ Failed to stop OctoFlow:", error)
  }
}

async function status() {
  // Check foreground mode (PID file)
  const foregroundRunning = await isRunning()
  
  // Check service mode (LaunchAgent/systemd)
  let serviceRunning = false
  const platform = process.platform
  
  if (platform === "darwin") {
    try {
      const result = execSync(`launchctl list | grep ${SERVICE_LABEL} || echo ""`, { encoding: "utf-8" })
      if (result.includes(SERVICE_LABEL)) {
        // Check if it has a PID (means it's actually running, not just loaded)
        const parts = result.trim().split(/\s+/)
        if (parts.length >= 2 && parts[0] !== "-") {
          serviceRunning = true
        }
      }
    } catch {}
  } else if (platform === "linux") {
    try {
      execSync("systemctl is-active --quiet octoflow")
      serviceRunning = true
    } catch {}
  }
  
  // Report status
  if (foregroundRunning && serviceRunning) {
    console.log("✓ OctoFlow is running (both foreground and service)")
  } else if (foregroundRunning) {
    console.log("✓ OctoFlow is running (foreground mode)")
    console.log("   Run: octoflow stop")
  } else if (serviceRunning) {
    console.log("✓ OctoFlow is running (service mode)")
    console.log("   Run: octoflow service stop")
  } else {
    console.log("✗ OctoFlow is not running")
    console.log("   Start with: octoflow start (foreground)")
    console.log("   Start with: octoflow service start (background)")
  }
}

async function logs() {
  console.log("📋 Recent logs will appear here when logging is implemented")
  console.log("   For now, run 'octoflow start' to see output in real-time")
}

async function installService() {
  const platform = process.platform
  
  if (platform === "darwin") {
    console.log("🍎 Installing macOS LaunchAgent...")
    await installMacOSLaunchAgent()
  } else if (platform === "linux") {
    console.log("🐧 Installing Linux systemd service...")
    await installLinuxService()
  } else {
    console.error(`❌ Unsupported platform: ${platform}`)
    process.exit(1)
  }
}

async function installMacOSLaunchAgent() {
  const plistPath = `${process.env.HOME}/Library/LaunchAgents/com.octoflow.app.plist`
  const logPath = `${REPO_ROOT}/octoflow.log`
  const errorLogPath = `${REPO_ROOT}/octoflow.error.log`
  
  // Detect opencode location
  let opencodePath = ""
  try {
    opencodePath = execSync("which opencode", { encoding: "utf-8" }).trim()
  } catch {
    // opencode not in PATH, try common locations
    const commonPaths = [
      "/opt/homebrew/bin/opencode",
      "/usr/local/bin/opencode",
      `${process.env.HOME}/.local/bin/opencode`,
    ]
    for (const p of commonPaths) {
      try {
        await Bun.file(p).text()
        opencodePath = p
        break
      } catch {}
    }
  }
  
  // Extract directory from opencode path
  const opencodeDir = opencodePath ? opencodePath.replace(/\/opencode$/, "") : ""
  
  const pathEnv = opencodeDir 
    ? `${process.env.HOME}/.bun/bin:${opencodeDir}:/usr/local/bin:/usr/bin:/bin`
    : `${process.env.HOME}/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`
  
  const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.octoflow.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>${process.env.HOME}/.bun/bin/bun</string>
        <string>${REPO_ROOT}/src/index.ts</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${REPO_ROOT}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${pathEnv}</string>
        <key>OPENCODE_CONFIG_DIR</key>
        <string>${REPO_ROOT}</string>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${logPath}</string>
    <key>StandardErrorPath</key>
    <string>${errorLogPath}</string>
</dict>
</plist>`

  try {
    await Bun.write(plistPath, plistContent)
    console.log(`✓ LaunchAgent created: ${plistPath}`)
    
    console.log("")
    console.log("📝 Service commands:")
    console.log("   octoflow service start    - Start service")
    console.log("   octoflow service stop     - Stop service")
    console.log("   octoflow service restart  - Restart service")
    console.log("   octoflow service status   - Check status")
    console.log("")
    console.log("📝 View logs:")
    console.log("   octoflow logs")
  } catch (error) {
    console.error("❌ Failed to install LaunchAgent:", error)
    process.exit(1)
  }
}

async function installLinuxService() {
  const servicePath = "/etc/systemd/system/octoflow.service"
  
  const serviceContent = `[Unit]
Description=OctoFlow AI Assistant
After=network.target

[Service]
Type=simple
User=${process.env.USER}
WorkingDirectory=${REPO_ROOT}
ExecStart=${process.env.HOME}/.bun/bin/bun ${REPO_ROOT}/src/index.ts
Environment="HOME=${process.env.HOME}"
Environment="OPENCODE_CONFIG_DIR=${REPO_ROOT}"
EnvironmentFile=-${REPO_ROOT}/.env
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target`

  try {
    // Write to temp file first, then use sudo to copy
    const tempPath = "/tmp/octoflow.service"
    await Bun.write(tempPath, serviceContent)
    
    execSync(`sudo cp "${tempPath}" "${servicePath}"`, { stdio: "inherit" })
    execSync("sudo systemctl daemon-reload", { stdio: "inherit" })
    execSync("sudo systemctl enable octoflow", { stdio: "inherit" })
    
    console.log("✓ systemd service installed")
    console.log("")
    console.log("Service commands:")
    console.log("  sudo systemctl start octoflow   - Start")
    console.log("  sudo systemctl stop octoflow    - Stop")
    console.log("  sudo systemctl status octoflow  - Status")
    console.log("  sudo journalctl -u octoflow -f  - View logs")
  } catch (error) {
    console.error("❌ Failed to install systemd service:", error)
    process.exit(1)
  }
}

async function setup() {
  const proc = Bun.spawn({
    cmd: ["bun", "src/cli/setup.ts"],
    cwd: REPO_ROOT,
    stdio: ["inherit", "inherit", "inherit"],
  })

  await proc.exited
}

// Service management commands
const PLIST_PATH = `${process.env.HOME}/Library/LaunchAgents/com.octoflow.app.plist`
const SERVICE_LABEL = "com.octoflow.app"

async function serviceStart() {
  const platform = process.platform
  
  if (platform === "darwin") {
    try {
      // Check if plist exists
      await Bun.file(PLIST_PATH).text()
      
      // Try to load the service
      try {
        execSync(`launchctl load "${PLIST_PATH}"`, { stdio: "inherit" })
        console.log("✓ OctoFlow service started")
      } catch {
        // Maybe already loaded, try to start it
        try {
          execSync(`launchctl start ${SERVICE_LABEL}`, { stdio: "inherit" })
          console.log("✓ OctoFlow service started")
        } catch (error) {
          console.error("❌ Failed to start service:", error)
        }
      }
    } catch {
      console.error("❌ LaunchAgent not found. Run 'octoflow install-service' first.")
    }
  } else if (platform === "linux") {
    try {
      execSync("sudo systemctl start octoflow", { stdio: "inherit" })
      console.log("✓ OctoFlow service started")
    } catch (error) {
      console.error("❌ Failed to start service:", error)
    }
  } else {
    console.error(`❌ Unsupported platform: ${platform}`)
  }
}

async function serviceStop() {
  const platform = process.platform
  
  if (platform === "darwin") {
    try {
      execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null || launchctl stop ${SERVICE_LABEL}`, { stdio: "inherit" })
      console.log("✓ OctoFlow service stopped")
    } catch {
      console.log("✓ OctoFlow service was not running")
    }
  } else if (platform === "linux") {
    try {
      execSync("sudo systemctl stop octoflow", { stdio: "inherit" })
      console.log("✓ OctoFlow service stopped")
    } catch {
      console.log("✓ OctoFlow service was not running")
    }
  } else {
    console.error(`❌ Unsupported platform: ${platform}`)
  }
}

async function serviceRestart() {
  await serviceStop()
  await new Promise(resolve => setTimeout(resolve, 1000))
  await serviceStart()
}

async function serviceStatus() {
  const platform = process.platform
  
  if (platform === "darwin") {
    try {
      const result = execSync(`launchctl list | grep ${SERVICE_LABEL} || echo "not found"`, { encoding: "utf-8" })
      if (result.includes(SERVICE_LABEL)) {
        console.log("✓ OctoFlow service is installed")
        console.log("   Check Activity Monitor or run: launchctl list | grep octoflow")
      } else {
        console.log("✗ OctoFlow service is not running")
        console.log("   Run: octoflow service start")
      }
    } catch {
      console.log("✗ OctoFlow service is not installed")
      console.log("   Run: octoflow install-service")
    }
  } else if (platform === "linux") {
    try {
      execSync("systemctl status octoflow --no-pager", { stdio: "inherit" })
    } catch {
      console.log("✗ Service not running or not installed")
    }
  } else {
    console.error(`❌ Unsupported platform: ${platform}`)
  }
}

async function handleServiceCommand() {
  const subcommand = process.argv[3]
  
  switch (subcommand) {
    case "start":
      await serviceStart()
      break
    case "stop":
      await serviceStop()
      break
    case "restart":
      await serviceRestart()
      break
    case "status":
      await serviceStatus()
      break
    case "--help":
    case "-h":
    case "help":
    default:
      showServiceHelp()
      break
  }
}

async function main() {
  const command = process.argv[2]

  switch (command) {
    case "start":
      await start()
      break
    case "stop":
      await stop()
      break
    case "restart":
      await stop()
      await new Promise(resolve => setTimeout(resolve, 1000))
      await start()
      break
    case "status":
      await status()
      break
    case "logs":
      await logs()
      break
    case "install-service":
      await installService()
      break
    case "service":
      await handleServiceCommand()
      break
    case "setup":
      await setup()
      break
    case "dev":
      await dev()
      break
    case "--help":
    case "-h":
    case "help":
    default:
      showHelp()
      break
  }
}

void main().catch((error) => {
  console.error("Error:", error instanceof Error ? error.message : String(error))
  process.exit(1)
})
