#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/octoflow"
SERVICE_USER="octoflow"
REPO_URL="https://github.com/peerasak-u/OctoFlow.git"

# Track if we have any errors
HAS_ERRORS=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    HAS_ERRORS=1
}

log_step() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Check if command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    echo ""
    echo "=========================================="
    echo "  OctoFlow Installation Doctor"
    echo "=========================================="
    echo ""
    
    log_step "Checking sudo access..."
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo"
        echo ""
        echo "Please run:"
        echo "  sudo ./scripts/install-pi.sh"
        echo ""
        exit 1
    fi
    log_info "Running as root ✓"
    
    echo ""
    log_step "Checking system dependencies..."
    
    # Check git
    if check_command git; then
        log_info "git is installed ($(git --version | head -1)) ✓"
    else
        log_error "git is not installed"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y git"
        echo ""
    fi
    
    # Check curl
    if check_command curl; then
        log_info "curl is installed ✓"
    else
        log_error "curl is not installed"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y curl"
        echo ""
    fi
    
    # Check unzip
    if check_command unzip; then
        log_info "unzip is installed ✓"
    else
        log_error "unzip is not installed"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y unzip"
        echo ""
    fi
    
    echo ""
    log_step "Checking Bun installation..."
    
    BUN_PATH=""
    if check_command bun; then
        BUN_PATH=$(which bun)
        log_info "Bun found in PATH: $BUN_PATH ($(bun --version)) ✓"
    elif [ -x "$HOME/.bun/bin/bun" ]; then
        BUN_PATH="$HOME/.bun/bin/bun"
        log_info "Bun found at: $BUN_PATH ✓"
        echo ""
        echo "Add to your PATH:"
        echo "  export PATH=\"$HOME/.bun/bin:\$PATH\""
        echo ""
        echo "Or create a symlink:"
        echo "  sudo ln -sf $HOME/.bun/bin/bun /usr/local/bin/bun"
        echo ""
    elif [ -x "/usr/local/bin/bun" ]; then
        BUN_PATH="/usr/local/bin/bun"
        log_info "Bun found at: $BUN_PATH ✓"
    else
        log_error "Bun is not installed"
        echo ""
        echo "Install Bun with:"
        echo "  curl -fsSL https://bun.sh/install | bash"
        echo ""
        echo "Then either:"
        echo "  1. Add to PATH: export PATH=\"\$HOME/.bun/bin:\$PATH\""
        echo "  2. Create symlink: sudo ln -sf \$HOME/.bun/bin/bun /usr/local/bin/bun"
        echo ""
    fi
    
    if [ $HAS_ERRORS -ne 0 ]; then
        echo ""
        echo "=========================================="
        log_error "Some prerequisites are missing!"
        echo "=========================================="
        echo ""
        echo "Please install the missing dependencies and run this script again."
        echo ""
        exit 1
    fi
    
    echo ""
    echo "=========================================="
    log_info "All prerequisites are met! ✓"
    echo "=========================================="
    echo ""
}

# Create service user
create_service_user() {
    log_step "Creating service user..."
    if id "$SERVICE_USER" &>/dev/null; then
        log_warn "User '$SERVICE_USER' already exists"
    else
        useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$SERVICE_USER"
        log_info "Created user: $SERVICE_USER ✓"
    fi
}

# Clone repository
clone_repository() {
    log_step "Cloning repository..."
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
    
    git clone "$REPO_URL" "$INSTALL_DIR"
    log_info "Cloned to $INSTALL_DIR ✓"
}

# Set ownership
set_ownership() {
    log_step "Setting ownership..."
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    log_info "Ownership set to $SERVICE_USER:$SERVICE_USER ✓"
}

# Generate CLI wrapper
generate_cli_wrapper() {
    log_step "Installing octoflow CLI..."
    
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
        echo "Updating OctoFlow..."
        cd $WORK_DIR
        sudo -u $SERVICE_USER git pull
        sudo -u $SERVICE_USER bun install
        systemctl restart $SERVICE_NAME
        echo "Update complete"
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
    log_info "CLI installed to $wrapper_path ✓"
}

# Install dependencies and run setup
run_setup() {
    log_step "Installing dependencies and running setup..."
    echo ""
    
    # Detect Bun path again (in case it was just installed)
    if check_command bun; then
        BUN_PATH=$(which bun)
    elif [ -x "$HOME/.bun/bin/bun" ]; then
        BUN_PATH="$HOME/.bun/bin/bun"
    elif [ -x "/usr/local/bin/bun" ]; then
        BUN_PATH="/usr/local/bin/bun"
    fi
    
    sudo -u "$SERVICE_USER" bash -c "
        export PATH=\"$(dirname $BUN_PATH):\$PATH\"
        export BUN_PATH=\"$BUN_PATH\"
        cd $INSTALL_DIR
        bun install
        bun run setup
    "
}

# Main installation
main() {
    # Check all prerequisites first
    check_prerequisites
    
    echo ""
    read -p "Continue with installation? [Y/n]: " response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    echo ""
    echo "=========================================="
    echo "  Installing OctoFlow..."
    echo "=========================================="
    echo ""
    
    create_service_user
    clone_repository
    set_ownership
    generate_cli_wrapper
    run_setup
    
    echo ""
    echo "=========================================="
    log_info "Installation complete! ✓"
    echo "=========================================="
    echo ""
    echo "Quick commands:"
    echo "  octoflow status    - Check service status"
    echo "  octoflow logs      - View logs"
    echo "  octoflow --help    - Show all commands"
    echo ""
}

# Run main function
main "$@"
