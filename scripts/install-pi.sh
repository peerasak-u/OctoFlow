#!/usr/bin/env bash
set -e

# OctoFlow Installer - Cross-Platform Setup
# Works on: Linux (systemd) and macOS

REPO_URL="https://github.com/peerasak-u/OctoFlow.git"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
IS_MACOS=false
IS_LINUX=false

if [ "$OS" = "darwin" ]; then
    IS_MACOS=true
    INSTALL_DIR="/usr/local/opt/octoflow"
    SERVICE_USER="_octoflow"
elif [ "$OS" = "linux" ]; then
    IS_LINUX=true
    INSTALL_DIR="/opt/octoflow"
    SERVICE_USER="octoflow"
else
    echo "Unsupported OS: $OS"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}→${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}[$1]${NC} $2"; }

# Check if running with appropriate permissions
check_system() {
    step "1/5" "Checking system..."
    
    if $IS_LINUX; then
        if [ "$EUID" -ne 0 ]; then
            error "Linux: Please run with sudo"
        fi
        info "Linux with sudo ✓"
    elif $IS_MACOS; then
        info "macOS detected"
        # On macOS, we'll use the current user, not create a system user
        SERVICE_USER="$(whoami)"
    fi
}

# Install system dependencies
install_deps() {
    step "2/5" "Installing system dependencies..."
    
    if $IS_LINUX; then
        apt-get update -qq
        apt-get install -y -qq git curl unzip
        info "Packages installed ✓"
    elif $IS_MACOS; then
        # Check for git and curl (usually pre-installed on macOS)
        if ! command -v git &>/dev/null; then
            error "Git not found. Please install Xcode Command Line Tools: xcode-select --install"
        fi
        if ! command -v curl &>/dev/null; then
            error "curl not found"
        fi
        info "Dependencies available ✓"
    fi
}

# Install Bun
install_bun() {
    step "3/5" "Setting up Bun..."
    
    if command -v bun &>/dev/null; then
        info "Bun already installed ($(bun --version)) ✓"
        return
    fi
    
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    
    # Add to current shell session
    export PATH="$HOME/.bun/bin:$PATH"
    
    # Create symlink
    if [ -f "$HOME/.bun/bin/bun" ]; then
        if $IS_LINUX; then
            ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
        elif $IS_MACOS; then
            sudo ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun 2>/dev/null || \
            ln -sf "$HOME/.bun/bin/bun" "$HOME/.local/bin/bun" 2>/dev/null || true
        fi
    fi
    
    # Verify
    if ! command -v bun &>/dev/null && [ ! -x "$HOME/.bun/bin/bun" ]; then
        error "Bun installation failed"
    fi
    
    info "Bun installed ✓"
}

# Setup Application
setup_app() {
    step "4/5" "Setting up OctoFlow..."
    
    # Create install directory
    if $IS_LINUX; then
        mkdir -p "$INSTALL_DIR"
        # Create service user on Linux
        if ! id "$SERVICE_USER" &>/dev/null; then
            useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SERVICE_USER"
            info "Created user: $SERVICE_USER"
        fi
    elif $IS_MACOS; then
        # On macOS, install to user directory if /usr/local/opt not writable
        if [ ! -w "/usr/local/opt" ] 2>/dev/null; then
            INSTALL_DIR="$HOME/.local/opt/octoflow"
            info "Installing to user directory: $INSTALL_DIR"
        fi
        mkdir -p "$INSTALL_DIR"
    fi
    
    # Clone or update repository
    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Updating existing installation..."
        cd "$INSTALL_DIR"
        git pull --quiet
    else
        if [ -d "$INSTALL_DIR" ]; then
            warn "Directory exists but is not a git repo. Backing up..."
            mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%s)"
        fi
        git clone --quiet "$REPO_URL" "$INSTALL_DIR"
        info "Cloned repository"
    fi
    
    # Set ownership (Linux only)
    if $IS_LINUX; then
        chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    fi
    
    info "App setup complete ✓"
}

# Install dependencies and configure
configure() {
    step "5/5" "Installing app dependencies..."
    
    cd "$INSTALL_DIR"
    
    # Install dependencies
    if $IS_LINUX; then
        sudo -u "$SERVICE_USER" bash -c "
            export PATH=\"/usr/local/bin:\$HOME/.bun/bin:\$PATH\"
            cd $INSTALL_DIR
            bun install
        "
    elif $IS_MACOS; then
        bun install
    fi
    
    info "Dependencies installed ✓"
    
    echo ""
    info "Running configuration..."
    echo ""
    
    # Run setup
    if $IS_LINUX; then
        sudo -u "$SERVICE_USER" bash -c "
            export PATH=\"/usr/local/bin:\$HOME/.bun/bin:\$PATH\"
            cd $INSTALL_DIR
            bun run setup
        " || true
    elif $IS_MACOS; then
        bun run setup || true
    fi
}

# Install service and CLI
install_service() {
    echo ""
    
    if $IS_LINUX; then
        info "Installing systemd service..."
        
        cat > /etc/systemd/system/octoflow.service << EOF
[Unit]
Description=OctoFlow AI Assistant
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/bun $INSTALL_DIR/src/index.ts
Environment="HOME=$INSTALL_DIR"
Environment="OPENCODE_CONFIG_DIR=$INSTALL_DIR"
EnvironmentFile=-$INSTALL_DIR/.env
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        # Create CLI wrapper
        cat > /usr/local/bin/octoflow << EOF
#!/usr/bin/env bash
WORK_DIR="$INSTALL_DIR"
SERVICE_NAME="octoflow"

case "\$1" in
    start) systemctl start \$SERVICE_NAME && echo "OctoFlow started" ;;
    stop) systemctl stop \$SERVICE_NAME && echo "OctoFlow stopped" ;;
    restart) systemctl restart \$SERVICE_NAME && echo "OctoFlow restarted" ;;
    status) systemctl status \$SERVICE_NAME --no-pager ;;
    logs) journalctl -u \$SERVICE_NAME -f ;;
    setup) sudo -u $SERVICE_USER bash -c "cd \$WORK_DIR && /usr/local/bin/bun run setup" ;;
    update) cd \$WORK_DIR && sudo -u $SERVICE_USER git pull && sudo -u $SERVICE_USER /usr/local/bin/bun install && systemctl restart \$SERVICE_NAME && echo "Updated!" ;;
    shell) sudo -u $SERVICE_USER bash -c "cd \$WORK_DIR && exec bash" ;;
    *)
        echo "OctoFlow CLI"
        echo ""
        echo "Usage: octoflow {command}"
        echo "  start, stop, restart, status, logs, setup, update, shell"
        ;;
esac
EOF
        chmod +x /usr/local/bin/octoflow
        
        systemctl daemon-reload
        systemctl enable octoflow --quiet
        
        info "Service installed ✓"
        
    elif $IS_MACOS; then
        info "Creating launchd service..."
        
        # Create launchd plist
        PLIST_PATH="$HOME/Library/LaunchAgents/com.octoflow.app.plist"
        mkdir -p "$HOME/Library/LaunchAgents"
        
        cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.octoflow.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.bun/bin/bun</string>
        <string>$INSTALL_DIR/src/index.ts</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>OPENCODE_CONFIG_DIR</key>
        <string>$INSTALL_DIR</string>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/octoflow.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/octoflow.error.log</string>
</dict>
</plist>
EOF

        # Create CLI wrapper for macOS
        CLI_PATH="$HOME/.local/bin/octoflow"
        mkdir -p "$HOME/.local/bin"
        
        cat > "$CLI_PATH" << EOF
#!/usr/bin/env bash
INSTALL_DIR="$INSTALL_DIR"

case "\$1" in
    start)
        launchctl load "$PLIST_PATH" 2>/dev/null || launchctl bootstrap gui/\$(id -u) "$PLIST_PATH"
        echo "OctoFlow started"
        ;;
    stop)
        launchctl unload "$PLIST_PATH" 2>/dev/null || launchctl bootout gui/\$(id -u) "$PLIST_PATH" 2>/dev/null
        echo "OctoFlow stopped"
        ;;
    restart)
        launchctl unload "$PLIST_PATH" 2>/dev/null
        launchctl load "$PLIST_PATH" 2>/dev/null || launchctl bootstrap gui/\$(id -u) "$PLIST_PATH"
        echo "OctoFlow restarted"
        ;;
    status)
        if launchctl list | grep -q com.octoflow.app; then
            echo "OctoFlow is running"
        else
            echo "OctoFlow is not running"
        fi
        ;;
    logs)
        tail -f "$INSTALL_DIR/octoflow.log"
        ;;
    setup)
        cd "\$INSTALL_DIR" && bun run setup
        ;;
    update)
        cd "\$INSTALL_DIR" && git pull && bun install
        echo "Updated! Run 'octoflow restart' to apply changes"
        ;;
    *)
        echo "OctoFlow CLI (macOS)"
        echo ""
        echo "Usage: octoflow {command}"
        echo "  start     Start the service"
        echo "  stop      Stop the service"
        echo "  restart   Restart the service"
        echo "  status    Check service status"
        echo "  logs      View logs"
        echo "  setup     Re-run setup wizard"
        echo "  update    Pull updates"
        echo ""
        echo "Note: Add ~/.local/bin to your PATH:"
        echo '  export PATH="$HOME/.local/bin:$PATH"'
        ;;
esac
EOF
        chmod +x "$CLI_PATH"
        
        info "LaunchAgent created ✓"
        warn "Add to your PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# Main
main() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  OctoFlow Installer"
    echo "  Platform: $([ "$IS_MACOS" = true ] && echo "macOS" || echo "Linux")"
    echo "═══════════════════════════════════════════"
    echo ""
    
    check_system
    install_deps
    install_bun
    setup_app
    configure
    install_service
    
    echo ""
    echo "═══════════════════════════════════════════"
    info "Installation Complete!"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "Location: $INSTALL_DIR"
    echo ""
    
    if $IS_LINUX; then
        echo "OctoFlow is installed as a systemd service."
        echo ""
        echo "Commands:"
        echo "  octoflow start    - Start the service"
        echo "  octoflow status   - Check status"
        echo "  octoflow logs     - View logs"
        echo ""
        echo "To start now: sudo octoflow start"
    elif $IS_MACOS; then
        echo "OctoFlow is installed as a user LaunchAgent."
        echo ""
        echo "Commands:"
        echo "  octoflow start    - Start the service"
        echo "  octoflow status   - Check status"
        echo "  octoflow logs     - View logs"
        echo ""
        echo "Add to your ~/.zshrc or ~/.bash_profile:"
        echo '  export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        echo "Then start with: octoflow start"
    fi
    echo ""
}

main "$@"
