# OctoFlow

OctoFlow is a minimal AI assistant built on the OpenCode SDK.

- **Telegram bot** (via `grammy`)
- **Simple memory** (single markdown file)
- **Proactive messaging** (via `save_memory` tool)
- **Periodic tasks** (heartbeat runner)
- **Access control** (channel whitelist)

## Quick Start

### 1. Clone & Install

```bash
git clone https://github.com/peerasak-u/OctoFlow.git
cd OctoFlow
bun install
```

### 2. Install CLI Globally

```bash
bun link
```

Now you can use `octoflow` from anywhere.

### 3. Configure

```bash
octoflow setup
```

This will:
- Ask for your Telegram bot token (get one from [@BotFather](https://t.me/botfather))
- Set up OpenCode authentication
- Create `.env` file

### 4. Run

**Option A: Foreground mode** (for testing, shows logs)
```bash
octoflow start
# Press Ctrl+C to stop
```

**Option B: Background service** (runs even after you close terminal)
```bash
# Install service (one-time setup)
octoflow install-service

# Start/stop service
octoflow service start
octoflow service stop
octoflow service restart
octoflow service status
```

## CLI Commands

```bash
octoflow --help              # Show all commands

# Foreground mode (development/testing)
octoflow start               # Start bot in terminal
octoflow stop                # Stop foreground bot
octoflow dev                 # Start with auto-reload
octoflow status              # Check if running

# Background service (production)
octoflow install-service     # Install LaunchAgent/service
octoflow service start       # Start background service
octoflow service stop        # Stop background service
octoflow service restart     # Restart service
octoflow service status      # Check service status

# Configuration
octoflow setup               # Run setup wizard
octoflow logs                # View recent logs
```

## Platform Notes

### macOS
- No sudo required
- Uses LaunchAgent (user-level service)
- Install with: `bun link`
- Service runs automatically on login after `install-service`

### Linux (Raspberry Pi, etc.)
- Same commands as macOS
- Uses systemd (requires sudo for service install)
- Service runs as current user

## Telegram Commands

Once your bot is running, message it on Telegram:

- **Any message** - Chat with the AI assistant
- `/remember <text>` - Save something to memory permanently
- `/new` - Start a new conversation session
- `/pair <token>` - Whitelist your account (if pair token is set)

## Project Structure

```
OctoFlow/
├── src/
│   ├── index.ts              # Main entry point
│   ├── cli/                  # CLI commands
│   │   ├── octoflow.ts       # Main CLI
│   │   └── setup.ts          # Setup wizard
│   ├── channels/
│   │   └── telegram.ts       # Telegram bot adapter
│   └── core/
│       └── assistant.ts      # OpenCode integration
├── .data/                    # Runtime data (created automatically)
│   ├── workspace/
│   │   └── MEMORY.md         # Bot's memory
│   ├── sessions.json         # Session storage
│   └── whitelist.json        # Allowed users
├── .env                      # Your config (created by setup)
└── package.json
```

## Environment Variables

The `octoflow setup` command creates a `.env` file. You can also edit it manually:

```bash
# Required
TELEGRAM_BOT_TOKEN=your_token_here
ENABLE_TELEGRAM=true

# Optional
OPENCODE_MODEL=provider/model        # Default model
WHITELIST_PAIR_TOKEN=secret123       # For /pair command
HEARTBEAT_INTERVAL_MINUTES=30        # Periodic task interval
```

## Development

```bash
# Run in development mode (auto-reload on file changes)
bun run dev

# Type check
bun run typecheck

# Test OpenCode connection
bun run test:opencode:e2e
```

## How It Works

1. **OpenCode SDK**: The bot uses OpenCode's SDK to communicate with AI models
2. **Memory**: Each message includes context from `MEMORY.md`
3. **Tools**: The bot can call `save_memory` to update its own memory
4. **Heartbeat**: Periodically runs tasks from `.data/heartbeat.md`
5. **Multi-channel**: Supports Telegram (more channels can be added)

## Troubleshooting

**"Command not found: octoflow"**
```bash
# Make sure bun is in your PATH
export PATH="$HOME/.bun/bin:$PATH"

# Re-link if needed
cd OctoFlow && bun link
```

**Service won't start**
```bash
# Check logs
tail -f ~/Workspace/indie/MonClaw/octoflow.error.log

# Try foreground mode to see errors
octoflow start
```

**Telegram bot not responding**
- Make sure your bot token is correct in `.env`
- Check that `ENABLE_TELEGRAM=true` is set
- Try restarting: `octoflow service restart`

## License

MIT - Use at your own risk. This is experimental software.
