#!/bin/bash

# ==============================================================================
# Mobiadd (Semaphore) Auto-Installer for macOS
# Aligned with setup.sh workflow
# ==============================================================================

# --- Safety & Error Handling ---
set -euo pipefail
IFS=$'\n\t'

# Cleanup on exit
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# --- Configuration ---
APP_NAME="mobiadd"
GO_VERSION="1.25.4" # Aligned with setup.sh
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
PLIST_PATH="/Library/LaunchDaemons/com.${APP_NAME}.server.plist"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# --- Helpers ---
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if running as root
is_root() {
    [ "$EUID" -eq 0 ]
}

# Get real user (if sudo used)
get_real_user() {
    if is_root; then
        echo "${SUDO_USER:-$USER}"
    else
        echo "$USER"
    fi
}

REAL_USER=$(get_real_user)
REAL_HOME=$(eval echo "~$REAL_USER")

# Run command as real user (for Homebrew/Build)
run_as_user() {
    if is_root; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# Require root for system changes
require_root() {
    if ! is_root; then
        echo -e "${YELLOW}This step requires root privileges. Please enter your password.${NC}"
        sudo "$@"
    else
        "$@"
    fi
}

# --- Steps ---

step_check_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is optimized for macOS. Detected: $(uname)"
        exit 1
    fi
    log_info "Detected macOS. Running as user: $REAL_USER"
}

step_install_deps() {
    log_info "[1/7] Installing System Dependencies..."
    
    # Check Homebrew
    if ! command -v brew &> /dev/null; then
        log_warn "Homebrew not found. Installing..."
        if is_root; then
            log_error "Cannot install Homebrew as root. Please run this script without sudo first."
            exit 1
        fi
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install deps as user (Aligned with setup.sh deps)
    log_info "Installing dependencies via Homebrew..."
    run_as_user brew install git node mysql wget
    
    log_success "Dependencies ready."
}

step_install_go() {
    log_info "[2/7] Installing Go ${GO_VERSION}..."
    
    # Always install the specific version requested in setup.sh
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) GO_ARCH="amd64" ;;
        arm64) GO_ARCH="arm64" ;;
        *) log_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    TEMP_DIR=$(mktemp -d)
    GO_FILE="go${GO_VERSION}.darwin-${GO_ARCH}.tar.gz"
    
    cd "$TEMP_DIR"
    log_info "Downloading $GO_FILE..."
    wget -q --show-progress "https://go.dev/dl/${GO_FILE}"
    
    # Install to /usr/local/go (requires root)
    log_info "Extracting Go to /usr/local/go..."
    require_root rm -rf /usr/local/go
    require_root tar -C /usr/local -xzf "$GO_FILE"
    
    # Setup paths for this session
    export PATH=$PATH:/usr/local/go/bin
    
    # Persist paths for user
    SHELL_RC="$REAL_HOME/.zshrc"
    if ! grep -q "/usr/local/go/bin" "$SHELL_RC"; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "$SHELL_RC"
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$SHELL_RC"
        chown "$REAL_USER" "$SHELL_RC"
    fi
    
    log_success "Go installed."
}

step_install_build_tools() {
    log_info "[3/7] Installing Go tools (task, goreleaser)..."
    
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH="$REAL_HOME/go"
    export PATH=$PATH:$GOPATH/bin
    
    run_as_user go install github.com/go-task/task/v3/cmd/task@latest
    run_as_user go install github.com/goreleaser/goreleaser/v2@latest
    
    log_success "Build tools ready."
}

step_build_app() {
    log_info "[4/7] Building project with goreleaser..."
    
    BUILD_DIR=$(mktemp -d)
    if is_root; then chown "$REAL_USER" "$BUILD_DIR"; fi
    
    cd "$BUILD_DIR"
    
    log_info "Cloning repository..."
    run_as_user git clone --depth 1 "$REPO_URL" .
    
    log_info "Installing project dependencies..."
    export PATH=$PATH:$REAL_HOME/go/bin
    run_as_user task deps
    
    log_info "Building Binary..."
    # Aligned with setup.sh build command
    run_as_user goreleaser release --snapshot --clean --skip=sign
    
    # Find binary
    BINARY_SRC=$(find dist -name "semaphore_darwin_*" -type d | head -n 1)/semaphore
    
    if [ ! -f "$BINARY_SRC" ]; then
        log_error "Build failed. Binary not found."
        exit 1
    fi
    
    log_info "[5/7] Installing package..."
    require_root cp "$BINARY_SRC" "$INSTALL_DIR/$APP_NAME"
    require_root chmod +x "$INSTALL_DIR/$APP_NAME"
    
    log_success "Binary installed."
}

step_configure() {
    log_info "[6/7] Setting up user and configuration..."
    
    require_root mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    require_root chmod 755 "$CONFIG_DIR" "$LOG_DIR"
    
    CONFIG_FILE="$CONFIG_DIR/config.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Generating configuration..."
        
        # Check MySQL
        if ! brew services list | grep mysql | grep started >/dev/null; then
            log_warn "MySQL is not running. Starting it..."
            run_as_user brew services start mysql
            sleep 5
        fi
        
        # Create DB
        run_as_user mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${APP_NAME};" 2>/dev/null || true
        
        # Generate random secrets (Aligned with setup.sh)
        COOKIE_HASH=$(openssl rand -base64 32)
        COOKIE_ENCRYPTION=$(openssl rand -base64 32)
        ACCESS_KEY_ENCRYPTION=$(openssl rand -base64 32)
        
        # Create config file directly (Aligned with setup.sh structure)
        TEMP_CONFIG=$(mktemp)
        cat <<EOF > "$TEMP_CONFIG"
{
    "mysql": {
        "host": "127.0.0.1:3306",
        "user": "root",
        "pass": "",
        "name": "${APP_NAME}"
    },
    "dialect": "mysql",
    "port": ":4000",
    "interface": "",
    "tmp_path": "/tmp/${APP_NAME}",
    "cookie_hash": "$COOKIE_HASH",
    "cookie_encryption": "$COOKIE_ENCRYPTION",
    "access_key_encryption": "$ACCESS_KEY_ENCRYPTION",
    "email_alert": false,
    "ldap_enable": false,
    "max_parallel_tasks": 10
}
EOF
        require_root mv "$TEMP_CONFIG" "$CONFIG_FILE"
        require_root chmod 644 "$CONFIG_FILE"
        
        # Run migrations
        log_info "Running database migrations..."
        "$INSTALL_DIR/$APP_NAME" migrate --config "$CONFIG_FILE"
        
        # Create Admin
        log_info "Creating Admin User..."
        "$INSTALL_DIR/$APP_NAME" user add --admin \
            --login admin \
            --email "admin@localhost" \
            --password "Mobiadd" \
            --name "Administrator" \
            --config "$CONFIG_FILE" || true
            
        log_success "Configuration created."
    else
        log_info "Config exists."
    fi
}

step_install_service() {
    log_info "[7/7] Setting up service..."
    
    # Create plist
    TEMP_PLIST=$(mktemp)
    cat <<EOF > "$TEMP_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.${APP_NAME}.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$APP_NAME</string>
        <string>server</string>
        <string>--config</string>
        <string>$CONFIG_FILE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/output.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

    require_root mv "$TEMP_PLIST" "$PLIST_PATH"
    require_root chown root:wheel "$PLIST_PATH"
    require_root chmod 644 "$PLIST_PATH"
    
    # Reload service
    log_info "Reloading service..."
    if require_root launchctl list "com.${APP_NAME}.server" &>/dev/null; then
        require_root launchctl unload "$PLIST_PATH"
    fi
    require_root launchctl load "$PLIST_PATH"
    
    log_success "Service installed and started."
}

finish() {
    echo -e "\n${GREEN}==============================================${NC}"
    echo -e "${GREEN}      🎉 macOS Installation Complete! ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "Web Interface:  ${BOLD}http://localhost:4000${NC}"
    echo -e "Admin User:     ${BOLD}admin${NC}"
    echo -e "Password:       ${BOLD}Mobiadd${NC}"
    echo -e "Config:         ${BOLD}$CONFIG_DIR/config.json${NC}"
    echo -e "Logs:           ${BOLD}$LOG_DIR${NC}"
    echo -e "${YELLOW}Note: Please change the password immediately!${NC}"
}

# --- Main ---
step_check_os
step_install_deps
step_install_go
step_install_build_tools
step_build_app
step_configure
step_install_service
finish