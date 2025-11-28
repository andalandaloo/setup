#!/bin/bash

# ==============================================================================
# Mobiadd (Semaphore) Master Installer
# Detects OS and launches the appropriate installation script
# ==============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Helpers ---
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# --- Main Logic ---

echo -e "${BLUE}${BOLD}"
cat << "EOF"
    __  ___      __    _            __    __
   /  |/  /___  / /_  (_)___ ______/ /___/ /
  / /|_/ / __ \/ __ \/ / __ `/ __  / __  / 
 / /  / / /_/ / /_/ / / /_/ / /_/ / /_/ /  
/_/  /_/\____/_.___/_/\__,_/\__,_/\__,_/   
                                           
    Powering Global Operators with Intelligent Telecom Solutions           
EOF
echo "=============================================="
echo -e "${NC}"

OS_TYPE=$(uname -s)
ARCH=$(uname -m)

log_info "System Detection:"
echo "  OS:   $OS_TYPE"
echo "  Arch: $ARCH"
echo ""

if [[ "$OS_TYPE" == "Linux" ]]; then
    log_info "Detected Linux. Downloading and running installer..."
    curl -fsSL https://gist.githubusercontent.com/andalandaloo/f7ddb94459af917ed0272308aa53370d/raw/5ce8caa7c6ff6fca9826f7a6ce4ecac922498f19/setup.sh | sudo bash

elif [[ "$OS_TYPE" == "Darwin" ]]; then
    log_info "Detected macOS. Downloading and running installer..."
    curl -fsSL https://gist.githubusercontent.com/andalandaloo/0f99ffbc1e4eb9a442b44e1678122a38/raw/216167d2632c07eff6c942821b5d1a3d0dc5f6f3/setup_macos.sh | sudo bash

elif [[ "$OS_TYPE" =~ CYGWIN|MINGW|MSYS ]]; then
    # Windows (Git Bash / WSL)
    log_warn "Detected Windows environment (Bash)."
    log_info "Please run 'setup.ps1' using PowerShell as Administrator."
    exit 1

else
    log_error "Unsupported Operating System: $OS_TYPE"
    exit 1
fi
