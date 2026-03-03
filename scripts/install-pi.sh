#!/usr/bin/env bash
set -e

# OctoFlow Installer - One Command Setup
# Usage: curl -fsSL https://raw.githubusercontent.com/peerasak-u/OctoFlow/main/scripts/install-pi.sh | sudo bash

INSTALL_DIR="/opt/octoflow"
SERVICE_USER="octoflow"
REPO_URL="https://github.com/peerasak-u/OctoFlow.git"

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

# Phase 1: System Check
check_system() {
    step "1/6" "Checking system..."
    
    if [ "$EUID" -ne 0 ]; then
        error "Please run with sudo: curl -fsSL ... | sudo bash"
    fi
    
    info "Running as root ✓"
}

# Phase 2: Install Dependencies
install_deps() {
    step "2/6" "Installing system dependencies..."
    
    apt-get update -qq
    apt-get install -y -qq git curl unzip
    info "Dependencies installed ✓"
}

# Phase 3: Install Bun
install_bun() {
    step "3/6" "Setting up Bun..."
    
    if command -v bun &>/dev/null; then
        info "Bun already installed ($(bun --version)) ✓"
        return
    fi
    
    if [ -x "/usr/local/bin/bun" ]; then
        info "Bun already installed ✓"
        return
    fi
    
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    
    # Create system-wide symlink
    if [ -f "$HOME/.bun/bin/bun" ]; then
        ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
        chmod +x /usr/local/bin/bun
    fi
    
    # Verify
    if ! command -v bun &>/dev/null && [ ! -x "/usr/local/bin/bun" ]; then
        error "Bun installation failed"
    fi
    
    info "Bun installed ✓"
}

# Phase 4: Setup Application
setup_app() {
    step "4/6" "Setting up OctoFlow..."
    
    # Create service user
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SERVICE_USER"
        info "Created user: $SERVICE_USER"
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
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    info "App setup complete ✓"
}

# Phase 5: Install Dependencies & Configure
configure() {
    step "5/6" "Installing app dependencies..."
    
    cd "$INSTALL_DIR"
    
    # Run as service user
    sudo -u "$SERVICE_USER" bash -c "
        export PATH=\"/usr/local/bin:\$HOME/.bun/bin:\$PATH\"
        cd $INSTALL_DIR
        bun install
    "
    
    info "Dependencies installed ✓"
    
    step "5/6" "Configuration (interactive)..."
    info "Please answer the following questions:"
    echo ""
    
    sudo -u "$SERVICE_USER" bash -c "
        export PATH=\"/usr/local/bin:\$HOME/.bun/bin:\$PATH\"
        cd $INSTALL_DIR
        bun run setup
    " || true
}

# Phase 6: Install Service & CLI
install_service() {
    step "6/6" "Installing systemd service..."
    
    # Create service file
    cat > /etc/systemd/system/octoflow.service << 'EOF'
[Unit]
Description=OctoFlow AI Assistant
After=network.target

[Service]
Type=simple
User=octoflow
Group=octoflow
WorkingDirectory=/opt/octoflow
ExecStart=/usr/local/bin/bun /opt/octoflow/src/index.ts
Environment="HOME=/opt/octoflow"
Environment="OPENCODE_CONFIG_DIR=/opt/octoflow"
EnvironmentFile=-/opt/octoflow/.env
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create CLI wrapper
    cat > /usr/local/bin/octoflow << 'EOF'
#!/usr/bin/env bash
WORK_DIR="/opt/octoflow"
SERVICE_NAME="octoflow"

case "$1" in
    start) systemctl start $SERVICE_NAME && echo "OctoFlow started" ;;
    stop) systemctl stop $SERVICE_NAME && echo "OctoFlow stopped" ;;
    restart) systemctl restart $SERVICE_NAME && echo "OctoFlow restarted" ;;
    status) systemctl status $SERVICE_NAME --no-pager ;;
    logs) journalctl -u $SERVICE_NAME -f ;;
    setup) sudo -u octoflow bash -c "cd $WORK_DIR && /usr/local/bin/bun run setup" ;;
    update) cd $WORK_DIR && sudo -u octoflow git pull && sudo -u octoflow /usr/local/bin/bun install && systemctl restart $SERVICE_NAME && echo "Updated!" ;;
    shell) sudo -u octoflow bash -c "cd $WORK_DIR && exec bash" ;;
    *)
        echo "OctoFlow CLI"
        echo ""
        echo "Usage: octoflow {command}"
        echo ""
        echo "Commands:"
        echo "  start     Start the service"
        echo "  stop      Stop the service"
        echo "  restart   Restart the service"
        echo "  status    Show service status"
        echo "  logs      View logs (follow)"
        echo "  setup     Re-run setup wizard"
        echo "  update    Pull updates and restart"
        echo "  shell     Open shell as octoflow user"
        echo ""
        ;;
esac
EOF

    chmod +x /usr/local/bin/octoflow
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable octoflow --quiet
    
    info "Service installed ✓"
}

# Main
main() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  OctoFlow Installer"
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
    echo "OctoFlow is now installed as a systemd service."
    echo ""
    echo "Quick commands:"
    echo "  octoflow start    - Start the service"
    echo "  octoflow stop     - Stop the service"
    echo "  octoflow status   - Check status"
    echo "  octoflow logs     - View logs"
    echo "  octoflow restart  - Restart service"
    echo ""
    echo "To start now: sudo octoflow start"
    echo ""
}

main "$@"
