#!/usr/bin/env bash
set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/ziroclaw"
SERVICE_USER="ziroclaw"

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
        exit 1
    fi
}

# Stop and disable service
stop_service() {
    log_info "Stopping ZiroClaw service..."
    systemctl stop ziroclaw 2>/dev/null || log_warn "Service was not running"
    
    log_info "Disabling ZiroClaw service..."
    systemctl disable ziroclaw 2>/dev/null || log_warn "Service was not enabled"
    
    if [ -f "/etc/systemd/system/ziroclaw.service" ]; then
        log_info "Removing service file..."
        rm -f "/etc/systemd/system/ziroclaw.service"
        systemctl daemon-reload
    fi
}

# Remove CLI wrapper
remove_cli_wrapper() {
    if [ -f "/usr/local/bin/ziroclaw" ]; then
        log_info "Removing CLI wrapper..."
        rm -f "/usr/local/bin/ziroclaw"
    fi
}

# Remove data directory
remove_data() {
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "This will delete all data including:"
        echo "  - Configuration files"
        echo "  - Session data"
        echo "  - Memory files"
        echo "  - Logs"
        echo ""
        read -p "Delete $INSTALL_DIR? [y/N]: " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log_info "Removing $INSTALL_DIR..."
            rm -rf "$INSTALL_DIR"
        else
            log_info "Keeping data directory at $INSTALL_DIR"
        fi
    fi
}

# Remove service user
remove_user() {
    if id "$SERVICE_USER" &>/dev/null; then
        read -p "Remove service user '$SERVICE_USER'? [y/N]: " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log_info "Removing user $SERVICE_USER..."
            userdel "$SERVICE_USER" 2>/dev/null || log_warn "Could not remove user"
        fi
    fi
}

# Main uninstallation
main() {
    log_info "Starting ZiroClaw uninstallation..."
    
    check_sudo
    
    stop_service
    remove_cli_wrapper
    remove_data
    remove_user
    
    echo ""
    log_info "Uninstallation complete!"
    echo ""
    echo "Note: Bun was not removed. To remove it manually:"
    echo "  sudo rm -f /usr/local/bin/bun"
    echo ""
}

# Run main function
main "$@"
