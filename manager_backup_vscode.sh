#!/usr/bin/env bash

# ============================================
# SISTEMA DE GESTIÓN DE BACKUPS VS CODE
# Versión: 1.0
# Autor: Víctor J. (https://github.com/maximovj)
# ============================================

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Detectar OS
OS="$(uname -s)"

# Configuración según plataforma
if [[ "$OS" == "Linux" ]] || [[ "$OS" == "Darwin" ]]; then
    # Linux y macOS
    VSCODE_CONFIG_DIR="$HOME/.config/Code"
    VSCODE_EXTENSIONS_DIR="$HOME/.vscode/extensions"
    VSCODE_CACHE_DIR="$HOME/.cache/vscode-cpptools"
elif [[ "$OS" =~ MINGW|CYGWIN|MSYS ]]; then
    # Windows (Git Bash, WSL, etc.)
    VSCODE_CONFIG_DIR="$APPDATA/Code"
    VSCODE_EXTENSIONS_DIR="$USERPROFILE/.vscode/extensions"
    VSCODE_CACHE_DIR="$USERPROFILE/AppData/Local/Temp/vscode-cpptools"
else
    echo "❌ Sistema no soportado"
    exit 1
fi

# Configuración
VSCODE_USER_DIR="$VSCODE_CONFIG_DIR/User"
BACKUP_BASE_DIR="$HOME/vscode_backups"
BACKUP_METADATA_FILE="$BACKUP_BASE_DIR/metadata.json"
EXPORT_DEFAULT_DIR="$HOME"
MAX_BACKUPS=20


# Crear directorio base si no existe
mkdir -p "$BACKUP_BASE_DIR"

# ============================================
# FUNCIONES AUXILIARES
# ============================================

print_header() {
    clear
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}  🚀 SISTEMA DE GESTIÓN DE BACKUPS VS CODE${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_separator() {
    echo -e "${CYAN}==========================================${NC}"
}

check_vscode() {
    if command -v code &> /dev/null; then
        VSCODE_VERSION=$(code --version | head -n1)
        print_success "VS Code detectado (versión: $VSCODE_VERSION)"
        return 0
    else
        print_error "VS Code no está instalado"
        return 1
    fi
}

get_size() {
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

get_backup_size() {
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

check_backup_dirs() {
    local backup_dir="$1"
    local has_config=false
    local has_extensions=false
    local has_cache=false
    
    if [ -d "$backup_dir/config" ]; then
        has_config=true
    fi
    if [ -d "$backup_dir/extensions" ]; then
        has_extensions=true
    fi
    if [ -d "$backup_dir/cache" ]; then
        has_cache=true
    fi
    
    echo "$has_config:$has_extensions:$has_cache"
}
