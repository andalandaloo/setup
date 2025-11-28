#!/bin/bash

# ==============================================================================
# Mobiadd (Semaphore) Master Installer
# Detects OS and launches the appropriate installation script
# ==============================================================================

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# --- Helpers ---
log_info()    { echo -e "${BLUE}ℹ️  ${BOLD}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}⚠️  ${BOLD}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}❌ ${BOLD}[ERR]${NC}  $1"; }

print_line() {
    echo -e "${DIM}------------------------------------------------------------${NC}"
}

# --- Main Logic ---

# Clear screen for a fresh start
# clear 

echo -e "${CYAN}${BOLD}"
cat << "EOF"
 ___ ___   ___   ____   ____   ____  ___    ___   
|   |   | /   \ |    \ |    | /    ||   \  |   \  
| _   _ ||     ||  o  ) |  | |  o  ||    \ |    \ 
|  \_/  ||  O  ||     | |  | |     ||  D  ||  D  |
|   |   ||     ||  O  | |  | |  _  ||     ||     |
|   |   ||     ||     | |  | |  |  ||     ||     |
|___|___| \___/ |_____||____||__|__||_____||_____|   
                                           
┏┓         •      ┏┓┓  ┓   ┓  ┏┓                   • ┓   ┳     ┓┓•         ┏┳┓  ┓          ┏┓  ┓   •     
┃┃┏┓┓┏┏┏┓┏┓┓┏┓┏┓  ┃┓┃┏┓┣┓┏┓┃  ┃┃┏┓┏┓┏┓┏┓╋┏┓┏┓┏  ┓┏┏┓╋┣┓  ┃┏┓╋┏┓┃┃┓┏┓┏┓┏┓╋   ┃ ┏┓┃┏┓┏┏┓┏┳┓  ┗┓┏┓┃┓┏╋┓┏┓┏┓┏
┣┛┗┛┗┻┛┗ ┛ ┗┛┗┗┫  ┗┛┗┗┛┗┛┗┻┗  ┗┛┣┛┗ ┛ ┗┻┗┗┛┛ ┛  ┗┻┛┗┗┛┗  ┻┛┗┗┗ ┗┗┗┗┫┗ ┛┗┗   ┻ ┗ ┗┗ ┗┗┛┛┗┗  ┗┛┗┛┗┗┻┗┗┗┛┛┗┛
               ┛                ┛                                  ┛                                     

EOF
echo -e "${NC}"
print_line

OS_TYPE=$(uname -s)
ARCH=$(uname -m)

echo -e "${PURPLE}🔍 System Detection:${NC}"
echo -e "   ${BOLD}OS:${NC}   $OS_TYPE"
echo -e "   ${BOLD}Arch:${NC} $ARCH"
print_line
echo ""

# Small delay for effect
sleep 0.5

if [[ "$OS_TYPE" == "Linux" ]]; then
    log_info "Detected Linux Environment."
    log_info "Fetching latest Linux installer..."
    echo ""
    curl -fsSL https://raw.githubusercontent.com/andalandaloo/setup/refs/heads/main/setup.sh | sudo bash

elif [[ "$OS_TYPE" == "Darwin" ]]; then
    log_info "Detected macOS Environment."
    log_info "Fetching latest macOS installer..."
    echo ""
    curl -fsSL https://raw.githubusercontent.com/andalandaloo/setup/refs/heads/main/setup_macos.sh | sudo bash

elif [[ "$OS_TYPE" =~ CYGWIN|MINGW|MSYS ]]; then
    # Windows (Git Bash / WSL)
    log_warn "Detected Windows environment (Bash)."
    echo ""
    echo -e "${YELLOW}Please run the PowerShell script instead:${NC}"
    echo -e "${BOLD}powershell -ExecutionPolicy Bypass -File setup.ps1${NC}"
    exit 1

else
    log_error "Unsupported Operating System: $OS_TYPE"
    echo -e "Please install manually."
    exit 1
fi
