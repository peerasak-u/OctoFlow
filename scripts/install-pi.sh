#!/usr/bin/env bash
set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/octoflow"
SERVICE_USER="octoflow"
REPO_URL="https://github.com/peerasak-u/OctoFlow.git"

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo or as root"
        log_info "Please run: curl -fsSL <url> | sudo bash"
        exit 1
    fi
}

# Detect existing Bun installation
detect_bun() {
    local bun_path=""
    
    # Check if bun is in PATH
    if command -v bun &> /dev/null; then
        bun_path=$(which bun)
        log_info "Found Bun in PATH: $bun_path"
        echo "$bun_path"
        return 0
    fi
    
    # Check common locations
    if [ -x "$HOME/.bun/bin/bun" ]; then
        bun_path="$HOME/.bun/bin/bun"
        log_info "Found Bun at: $bun_path"
        echo "$bun_path"
        return 0
    fi
    
    if [ -x "/usr/local/bin/bun" ]; then
        bun_path="/usr/local/bin/bun"
        log_info "Found Bun at: $bun_path"
        echo "$bun_path"
        return 0
    fi
    
    if [ -x "/opt/homebrew/bin/bun" ]; then
        bun_path="/opt/homebrew/bin/bun"
        log_info "Found Bun at: $bun_path"
        echo "$bun_path"
        return 0
    fi
    
    # Check BUN_INSTALL env var
    if [ -n "${BUN_INSTALL:-}" ] && [ -x "$BUN_INSTALL/bin/bun" ]; then
        bun_path="$BUN_INSTALL/bin/bun"
        log_info "Found Bun via BUN_INSTALL: $bun_path"
        echo "$bun_path"
        return 0
    fi
    
    return 1
}

# Install Bun system-wide
install_bun_systemwide() {
    log_info "Installing Bun system-wide..."
    
    # Use official Bun installer
    curl -fsSL https://bun.sh/install | bash
    
    # Create symlink for system-wide access
    if [ -f "$HOME/.bun/bin/bun" ]; then
        ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
        log_info "Bun installed to /usr/local/bin/bun"
        echo "/usr/local/bin/bun"
    else
        log_error "Bun installation failed"
        exit 1
    fi
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    apt-get update
    apt-get install -y git curl unzip
    log_info "Dependencies installed"
}

# Create service user
create_service_user() {
    if id "$SERVICE_USER" &>/dev/null; then
        log_warn "User '$SERVICE_USER' already exists"
    else
        log_info "Creating service user: $SERVICE_USER"
        useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SERVICE_USER"
    fi
}

# Clone repository
clone_repository() {
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "Directory $INSTALL_DIR already exists"
        read -p "Remove and re-clone? [y/N]: " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            log_info "Using existing directory"
            return 0
        fi
    fi
    
    log_info "Cloning repository to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
}

# Set ownership
set_ownership() {
    log_info "Setting ownership to $SERVICE_USER:$SERVICE_USER..."
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
}

# Generate CLI wrapper
generate_cli_wrapper() {
    log_info "Generating octoflow CLI wrapper..."
    
    local wrapper_path="/usr/local/bin/octoflow"
    
    cat > "$wrapper_path" << 'WRAPPER_EOF'
#!/usr/bin/env bash

WORK_DIR="/opt/octoflow"
SERVICE_NAME="octoflow"

show_help() {
    echo "OctoFlow CLI Wrapper"
    echo ""
    echo "Usage: octoflow {command}"
    echo ""
    echo "Commands:"
    echo "  start       Start the OctoFlow service"
    echo "  stop        Stop the OctoFlow service"
    echo "  restart     Restart the OctoFlow service"
    echo "  status      Show service status and health"
    echo "  logs        View service logs (follow mode)"
    echo "  setup       Re-run the setup wizard"
    echo "  update      Pull latest changes and restart"
    echo "  shell       Drop to octoflow user shell for debugging"
    echo "  help        Show this help message"
}

check_health() {
    local health_file="$WORK_DIR/.data/health.check"
    if [ -f "$health_file" ]; then
        local last=$(stat -c %Y "$health_file" 2>/dev/null || stat -f %m "$health_file" 2>/dev/null)
        local now=$(date +%s)
        local diff=$((now - last))
        if [ $diff -lt 300 ]; then
            echo "Health: OK (last check ${diff}s ago)"
        else
            echo "Health: STALE (last check ${diff}s ago)"
        fi
    else
        echo "Health: UNKNOWN (no health check file)"
    fi
}

case "$1" in
    start)
        systemctl start $SERVICE_NAME
        echo "OctoFlow started"
        ;;
    stop)
        systemctl stop $SERVICE_NAME
        echo "OctoFlow stopped"
        ;;
    restart)
        systemctl restart $SERVICE_NAME
        echo "OctoFlow restarted"
        ;;
    status)
        systemctl status $SERVICE_NAME --no-pager
        check_health
        ;;
    logs)
        journalctl -u $SERVICE_NAME -f
        ;;
    setup)
        sudo -u $SERVICE_USER bash -c "cd $WORK_DIR && bun run setup"
        ;;
    update)
        log_info "Updating OctoFlow..."
        cd $WORK_DIR
        sudo -u $SERVICE_USER git pull
        sudo -u $SERVICE_USER bun install
        systemctl restart $SERVICE_NAME
        log_info "Update complete"
        ;;
    shell)
        sudo -u $SERVICE_USER bash -c "cd $WORK_DIR && exec bash"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
WRAPPER_EOF

    chmod +x "$wrapper_path"
    log_info "CLI wrapper installed to $wrapper_path"
}

# Main installation
main() {
    log_info "Starting OctoFlow installation for Raspberry Pi..."
    
    # Check sudo
    check_sudo
    
    # Install dependencies
    install_dependencies
    
    # Detect or install Bun
    BUN_PATH=$(detect_bun || true)
    if [ -z "$BUN_PATH" ]; then
        log_info "Bun not found. Installing..."
        BUN_PATH=$(install_bun_systemwide)
    fi
    
    # Verify Bun works
    if ! "$BUN_PATH" --version &>/dev/null; then
        log_error "Bun installation failed or is not working"
        exit 1
    fi
    
    log_info "Using Bun: $BUN_PATH"
    
    # Create service user
    create_service_user
    
    # Clone repository
    clone_repository
    
    # Set ownership
    set_ownership
    
    # Generate CLI wrapper
    generate_cli_wrapper
    
    # Install dependencies and run setup
    log_info "Installing dependencies and running setup..."
    log_info "You will be prompted for configuration..."
    echo ""
    
    # Export Bun path for the setup
    export BUN_PATH
    sudo -u "$SERVICE_USER" bash -c "
        export PATH=\"$(dirname $BUN_PATH):\$PATH\"
        export BUN_PATH=\"$BUN_PATH\"
        cd $INSTALL_DIR
        bun install
        bun run setup
    "
    
    echo ""
    log_info "Installation complete!"
    echo ""
    echo "Quick start:"
    echo "  octoflow status    - Check service status"
    echo "  octoflow logs      - View logs"
    echo "  octoflow --help    - Show all commands"
    echo ""
}

# Run main function
main "$@"
