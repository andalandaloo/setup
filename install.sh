#!/bin/bash

# ==============================================================================
# Mobiadd Universal Installer
# Powering Global Operators with Intelligent Telecom Solutions
# ==============================================================================

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
MAGENTA='\033[1;35m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# --- Animation & Effects ---
print_gradient_line() {
    local colors=("${CYAN}" "${BLUE}" "${PURPLE}" "${MAGENTA}")
    local line="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for i in {0..3}; do
        echo -ne "${colors[$i]}${line:0:15}${NC}"
    done
    echo ""
}

print_telecom_icon() {
    echo -e "${CYAN}    ╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}    ║  ${MAGENTA}📡  ${CYAN}Global Network  ${PURPLE}•  ${CYAN}Intelligent Systems  ${MAGENTA}•  ${CYAN}5G Ready  ${MAGENTA}📶${CYAN}  ║${NC}"
    echo -e "${CYAN}    ╚═══════════════════════════════════════════════════════════╝${NC}"
}

animate_dots() {
    local msg="$1"
    echo -ne "${BLUE}${msg}${NC}"
    for i in {1..3}; do
        echo -ne "${CYAN}.${NC}"
        sleep 0.2
    done
    echo ""
}

# --- Helpers ---
log_info()    { echo -e "${CYAN}▶  ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}✓  ${BOLD}$1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠  ${BOLD}$1${NC}"; }
log_error()   { echo -e "${RED}✗  ${BOLD}$1${NC}"; }

# --- Main Display ---
clear

# Top border
echo ""
print_gradient_line

# ASCII Art Banner
echo -e "${MAGENTA}${BOLD}"
cat << "EOF"
 ___ ___   ___   ____   ____   ____  ___    ___   
|   |   | /   \ |    \ |    | /    ||   \  |   \  
| _   _ ||     ||  o  ) |  | |  o  ||    \ |    \ 
|  \_/  ||  O  ||     | |  | |     ||  D  ||  D  |
|   |   ||     ||  O  | |  | |  _  ||     ||     |
|   |   ||     ||     | |  | |  |  ||     ||     |
|___|___| \___/ |_____||____||__|__||_____||_____|
EOF
echo -e "${NC}"

# Tagline with icons
echo -e "${CYAN}    ┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}    │  ${PURPLE}⚡ ${BOLD}Powering Global Operators with Intelligent Solutions${NC} ${PURPLE}⚡${CYAN}  │${NC}"
echo -e "${CYAN}    └─────────────────────────────────────────────────────────────┘${NC}"
echo ""

# Telecom features
print_telecom_icon
echo ""

print_gradient_line

# System Detection
echo -e "${PURPLE}${BOLD}🔍 System Detection${NC}"
echo ""

OS_TYPE=$(uname -s)
ARCH=$(uname -m)

echo -e "   ${DIM}┌─ Platform${NC}"
echo -e "   ${CYAN}├─${NC} ${BOLD}OS:${NC}       ${GREEN}$OS_TYPE${NC}"
echo -e "   ${CYAN}└─${NC} ${BOLD}Arch:${NC}     ${GREEN}$ARCH${NC}"
echo ""

print_gradient_line
echo ""

# Animated loading
animate_dots "Initializing deployment sequence"
sleep 0.3

# Route to appropriate installer
if [[ "$OS_TYPE" == "Linux" ]]; then
    echo ""
    log_info "Linux environment detected"
    echo -e "${DIM}   Connecting to deployment server...${NC}"
    sleep 0.5
    log_success "Connection established"
    echo ""
    echo -e "${CYAN}${BOLD}   ╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}   ║  ${MAGENTA}Launching Linux Installation Protocol${NC}${CYAN}${BOLD}       ║${NC}"
    echo -e "${CYAN}${BOLD}   ╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    sleep 0.5
    curl -fsSL https://raw.githubusercontent.com/andalandaloo/setup/refs/heads/main/setup.sh | sudo bash

elif [[ "$OS_TYPE" == "Darwin" ]]; then
    echo ""
    log_info "macOS environment detected"
    echo -e "${DIM}   Connecting to deployment server...${NC}"
    sleep 0.5
    log_success "Connection established"
    echo ""
    echo -e "${CYAN}${BOLD}   ╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}   ║  ${MAGENTA}Launching macOS Installation Protocol${NC}${CYAN}${BOLD}        ║${NC}"
    echo -e "${CYAN}${BOLD}   ╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    sleep 0.5
    curl -fsSL https://raw.githubusercontent.com/andalandaloo/setup/refs/heads/main/setup_macos.sh | sudo bash

elif [[ "$OS_TYPE" =~ CYGWIN|MINGW|MSYS ]]; then
    echo ""
    log_warn "Windows environment detected (Bash)"
    echo ""
    echo -e "${YELLOW}   ┌────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}   │  Please use PowerShell for Windows installation   │${NC}"
    echo -e "${YELLOW}   └────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BOLD}   Run this command in PowerShell (as Administrator):${NC}"
    echo -e "${CYAN}   powershell -ExecutionPolicy Bypass -File setup.ps1${NC}"
    echo ""
    exit 1

else
    echo ""
    log_error "Unsupported Operating System: $OS_TYPE"
    echo ""
    echo -e "${RED}   ┌────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}   │  This platform is not currently supported         │${NC}"
    echo -e "${RED}   │  Please contact support for manual installation   │${NC}"
    echo -e "${RED}   └────────────────────────────────────────────────────┘${NC}"
    echo ""
    exit 1
fi
