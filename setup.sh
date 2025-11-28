#!/bin/bash

# ==============================================================================
# Mobiadd (Semaphore) Auto-Installer for Linux
# Supported: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch, openSUSE
# Best Practices: Robust Error Handling, Idempotency, Pre-flight Checks
# ==============================================================================

# --- Safety & Configuration ---
set -o errexit  # Exit on error
set -o nounset  # Exit on undefined variables
set -o pipefail # Exit if any command in a pipe fails
IFS=$'\n\t'

# --- Global Variables ---
APP_NAME="mobiadd"
REPO_URL="https://github.com/semaphoreui/semaphore.git"
GO_VERSION="1.23.4"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# --- Error Handling & Logging ---

log_info() { echo -e "${BLUE}ℹ️  [INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}✅ [OK]   $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  [WARN] $1${NC}" >&2; }
log_error() { echo -e "${RED}❌ [ERR]  $1${NC}" >&2; }

# Custom Error Handler
error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="${BASH_COMMAND}"
    
    echo -e "\n${RED}======================================================${NC}"
    echo -e "${RED}❌ FATAL ERROR OCCURRED${NC}"
    echo -e "${RED}======================================================${NC}"
    echo -e "Error on line: ${BOLD}$line_number${NC}"
    echo -e "Command:       ${BOLD}$command${NC}"
    echo -e "Exit Code:     ${BOLD}$exit_code${NC}"
    echo -e "${YELLOW}Tip: Check the logs above for more details.${NC}"
    
    cleanup
    exit $exit_code
}

trap 'error_handler ${LINENO}' ERR

# Cleanup Function
cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# --- Pre-flight Checks ---

check_requirements() {
    log_info "Running pre-flight checks..."
    
    # 1. Check Root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Try: sudo $0"
        exit 1
    fi
    
    # 2. Check Systemd
    if ! pidof systemd >/dev/null && ! [ -d /run/systemd/system ]; then
        log_warn "Systemd not detected. Service installation might fail."
    fi
    
    # 3. Check Internet
    if ! ping -c 1 google.com &>/dev/null; then
        log_warn "No internet connection detected. Installation might fail."
    fi
}

# --- Steps ---

step_detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    else
        DISTRO="unknown"
    fi
    
    log_info "Detected Linux Distribution: $DISTRO $DISTRO_VERSION"
}

# Helper to check if a package is installed
is_pkg_installed() {
    local pkg=$1
    case $DISTRO in
        ubuntu|debian|kali|pop|mint)
            dpkg -s "$pkg" &>/dev/null
            ;;
        centos|rhel|rocky|almalinux|fedora)
            rpm -q "$pkg" &>/dev/null
            ;;
        arch|manjaro)
            pacman -Qi "$pkg" &>/dev/null
            ;;
        opensuse*|sles)
            rpm -q "$pkg" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

step_install_deps() {
    log_info "[1/8] Checking & Installing System Dependencies..."
    
    # Fix broken installs first
    if command -v apt-get &>/dev/null; then
        apt-get --fix-broken install -y || true
    fi

    # Define base packages (excluding npm to avoid conflicts)
    local PACKAGES=("git" "curl" "wget" "mysql-server")
    
    # Add build tools based on distro
    case $DISTRO in
        ubuntu|debian|kali|pop|mint)
            PACKAGES+=("build-essential" "nodejs")
            ;;
        fedora|centos|rhel|rocky|almalinux)
            PACKAGES+=("gcc" "gcc-c++" "make" "nodejs")
            ;;
        arch|manjaro)
            PACKAGES+=("base-devel" "nodejs")
            ;;
        opensuse*|sles)
            PACKAGES+=("gcc" "gcc-c++" "make" "nodejs")
            ;;
    esac

    local TO_INSTALL=()

    # Check what needs to be installed
    for pkg in "${PACKAGES[@]}"; do
        if is_pkg_installed "$pkg"; then
            log_info "Package '$pkg' is already installed. Skipping."
        else
            TO_INSTALL+=("$pkg")
        fi
    done

    # Install missing packages
    if [ ${#TO_INSTALL[@]} -eq 0 ]; then
        log_success "All base dependencies are already installed."
    else
        log_info "Installing missing packages: ${TO_INSTALL[*]}"
        case $DISTRO in
            ubuntu|debian|kali|pop|mint)
                apt-get update -qq
                apt-get install -y "${TO_INSTALL[@]}"
                ;;
            fedora)
                dnf install -y "${TO_INSTALL[@]}"
                ;;
            centos|rhel|rocky|almalinux)
                yum install -y epel-release
                yum install -y "${TO_INSTALL[@]}"
                ;;
            arch|manjaro)
                pacman -Sy --noconfirm "${TO_INSTALL[@]}"
                ;;
            opensuse*|sles)
                zypper install -y "${TO_INSTALL[@]}"
                ;;
        esac
    fi
    
    # Handle NPM separately to avoid conflicts
    if ! command -v npm &>/dev/null; then
        log_info "npm command not found. Attempting to install 'npm' package..."
        case $DISTRO in
            ubuntu|debian|kali|pop|mint)
                # Only install npm if nodejs didn't provide it
                apt-get install -y npm || log_warn "Failed to install npm. It might be provided by nodejs."
                ;;
            fedora|centos|rhel|rocky|almalinux)
                yum install -y npm
                ;;
            arch|manjaro)
                pacman -S --noconfirm npm
                ;;
            opensuse*|sles)
                zypper install -y npm
                ;;
        esac
    else
        log_success "npm is already installed ($(npm -v))."
    fi
    
    log_success "Dependencies check complete."
}

step_install_go() {
    log_info "[2/8] Installing Go ${GO_VERSION}..."
    
    if command -v go &>/dev/null; then
        CURRENT=$(go version | awk '{print $3}' | sed 's/go//')
        if [ "$CURRENT" == "$GO_VERSION" ]; then
            log_success "Go $GO_VERSION already installed. Skipping."
            return
        fi
    fi
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) GO_ARCH="amd64" ;;
        aarch64|arm64) GO_ARCH="arm64" ;;
        armv7l) GO_ARCH="armv6l" ;;
        *) log_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    TEMP_DIR=$(mktemp -d)
    GO_FILE="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    
    cd "$TEMP_DIR"
    log_info "Downloading $GO_FILE..."
    if ! wget -q --show-progress "https://go.dev/dl/${GO_FILE}"; then
        log_error "Failed to download Go. Please check if version $GO_VERSION exists."
        exit 1
    fi
    
    log_info "Extracting to /usr/local/go..."
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$GO_FILE"
    
    export PATH=$PATH:/usr/local/go/bin
    
    for RC in ~/.bashrc /etc/profile.d/go.sh; do
        if ! grep -q "/usr/local/go/bin" "$RC" 2>/dev/null; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> "$RC"
            echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$RC"
        fi
    done
    chmod +x /etc/profile.d/go.sh 2>/dev/null || true
    
    log_success "Go installed."
}

step_install_build_tools() {
    log_info "[3/8] Installing Go tools..."
    
    export PATH=$PATH:/usr/local/go/bin
    export PATH=$PATH:$(go env GOPATH)/bin
    
    if ! command -v task &>/dev/null || ! task --version 2>&1 | grep -q "go-task"; then
        log_info "Installing go-task..."
        go install github.com/go-task/task/v3/cmd/task@latest
    else
        log_success "go-task already installed."
    fi

    if ! command -v goreleaser &>/dev/null; then
        log_info "Installing goreleaser..."
        go install github.com/goreleaser/goreleaser/v2@latest
    else
        log_success "goreleaser already installed."
    fi
    
    log_success "Build tools ready."
}

step_build_app() {
    log_info "[4/8] Building project..."
    
    TEMP_BUILD=$(mktemp -d)
    cd "$TEMP_BUILD"
    
    log_info "Cloning repository..."
    git clone --depth 1 "$REPO_URL" .
    
    log_info "Installing project dependencies..."
    task deps
    
    log_info "Building Binary..."
    goreleaser release --snapshot --clean --skip=sign
    
    BINARY_SRC=$(find dist -name "semaphore_linux_amd64_*" -type d | head -n 1)/semaphore
    
    if [ ! -f "$BINARY_SRC" ]; then
        BINARY_SRC=$(find dist -type f -name "semaphore" | head -n 1)
    fi
    
    if [ ! -f "$BINARY_SRC" ]; then
        log_error "Build failed. Binary not found in dist/."
        exit 1
    fi
    
    log_info "[5/8] Installing package..."
    cp "$BINARY_SRC" "$INSTALL_DIR/$APP_NAME"
    chmod +x "$INSTALL_DIR/$APP_NAME"
    
    log_success "Binary installed to $INSTALL_DIR/$APP_NAME"
}

step_configure() {
    log_info "[6/8] Configuring system..."
    
    if ! id -u ${APP_NAME} >/dev/null 2>&1; then
        useradd --system --home-dir /var/lib/${APP_NAME} --shell /usr/sbin/nologin ${APP_NAME}
    fi
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" /var/lib/${APP_NAME}
    chown -R ${APP_NAME}:${APP_NAME} "$CONFIG_DIR" "$LOG_DIR" /var/lib/${APP_NAME}
    chmod 750 "$CONFIG_DIR" /var/lib/${APP_NAME}
    
    CONFIG_FILE="$CONFIG_DIR/config.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Generating configuration..."
        
        if command -v mysql &>/dev/null; then
             systemctl start mysql || true
             mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${APP_NAME};" 2>/dev/null || true
        fi
        
        COOKIE_HASH=$(openssl rand -base64 32)
        COOKIE_ENCRYPTION=$(openssl rand -base64 32)
        ACCESS_KEY_ENCRYPTION=$(openssl rand -base64 32)
        
        cat <<EOF > "$CONFIG_FILE"
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
        chown ${APP_NAME}:${APP_NAME} "$CONFIG_FILE"
        chmod 640 "$CONFIG_FILE"
        
        log_info "Running migrations..."
        "$INSTALL_DIR/$APP_NAME" migrate --config "$CONFIG_FILE"
        
        log_info "Creating Admin User..."
        "$INSTALL_DIR/$APP_NAME" user add --admin \
            --login admin \
            --email "admin@localhost" \
            --password "Mobiadd" \
            --name "Administrator" \
            --config "$CONFIG_FILE" || true
            
        log_success "Configuration created."
    else
        log_info "Config exists. Skipping generation."
    fi
}

step_install_service() {
    log_info "[7/8] Setting up systemd service..."
    
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Mobiadd Automation Server
Documentation=https://github.com/semaphoreui/semaphore
After=network.target mysql.service

[Service]
Type=simple
User=${APP_NAME}
Group=${APP_NAME}
ExecStart=$INSTALL_DIR/$APP_NAME server --config $CONFIG_FILE
Restart=always
RestartSec=5s
Environment="SEMAPHORE_CONFIG=$CONFIG_FILE"
StandardOutput=append:$LOG_DIR/access.log
StandardError=append:$LOG_DIR/error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${APP_NAME}
    systemctl restart ${APP_NAME}
    
    if command -v ufw &>/dev/null; then
        ufw allow 4000/tcp >/dev/null || true
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=4000/tcp >/dev/null || true
        firewall-cmd --reload >/dev/null || true
    fi
    
    log_success "Service started."
}

step_verify() {
    log_info "[8/8] Verifying Installation..."
    
    sleep 5
    if systemctl is-active --quiet ${APP_NAME}; then
        log_success "Service is running."
    else
        log_error "Service failed to start. Check logs: journalctl -u ${APP_NAME}"
        exit 1
    fi
    
    if ss -ltn | grep -q ":4000"; then
        log_success "Port 4000 is listening."
    else
        log_warn "Port 4000 not detected yet. It might take a moment."
    fi
}

finish() {
    IP_ADDR=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    
    echo -e "\n${GREEN}==============================================${NC}"
    echo -e "${GREEN}      🎉 Linux Installation Complete! ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "Web Interface:  ${BOLD}http://${IP_ADDR}:4000${NC}"
    echo -e "Admin User:     ${BOLD}admin${NC}"
    echo -e "Password:       ${BOLD}Mobiadd${NC}"
    echo -e "Config:         ${BOLD}$CONFIG_DIR/config.json${NC}"
    echo -e "Logs:           ${BOLD}$LOG_DIR${NC}"
    echo -e "${YELLOW}Note: Please change the password immediately!${NC}"
}

# --- Main ---
check_requirements
step_detect_distro
step_install_deps
step_install_go
step_install_build_tools
step_build_app
step_configure
step_install_service
step_verify
finish
