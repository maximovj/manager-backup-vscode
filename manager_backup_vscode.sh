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

# ============================================
# DETECTAR SISTEMA OPERATIVO
# ============================================
OS="$(uname -s)"
case "$OS" in
    Linux*)     PLATFORM="linux" ;;
    Darwin*)    PLATFORM="macos" ;;
    CYGWIN*|MINGW*|MSYS*) PLATFORM="windows" ;;
    *)          PLATFORM="unknown" ;;
esac

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

# ============================================
# FUNCIÓN PARA FORMATEAR FECHA
# ============================================

format_date() {
    local date_str="$1"
    
    # Si la fecha contiene ":", tomar solo la parte del timestamp
    if [[ "$date_str" == *":"* ]]; then
        date_str=$(echo "$date_str" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
    fi
    
    # Si la fecha tiene formato YYYYMMDD_HHMMSS
    if [[ "$date_str" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        local year="${date_str:0:4}"
        local month="${date_str:4:2}"
        local day="${date_str:6:2}"
        local hour="${date_str:9:2}"
        local minute="${date_str:11:2}"
        local second="${date_str:13:2}"
        echo "${day}/${month}/${year} ${hour}:${minute}:${second}"
    else
        echo "$date_str"
    fi
}

# ============================================
# FUNCIÓN PARA INSTALAR JQ (según el sistema)
# ============================================
install_jq() {
    echo "📦 Verificando jq..."
    
    # Verificar si ya está instalado
    if command -v jq &> /dev/null; then
        echo "✅ jq ya está instalado: $(jq --version)"
        return 0
    fi
    
    echo "⚠️ jq no está instalado. Intentando instalar..."
    
    case "$PLATFORM" in
        linux)
            # Detectar distribución Linux
            if command -v apt-get &> /dev/null; then
                echo "📦 Usando apt-get (Debian/Ubuntu)..."
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                echo "📦 Usando yum (RHEL/CentOS/Fedora)..."
                sudo yum install -y jq
            elif command -v dnf &> /dev/null; then
                echo "📦 Usando dnf (Fedora)..."
                sudo dnf install -y jq
            elif command -v pacman &> /dev/null; then
                echo "📦 Usando pacman (Arch)..."
                sudo pacman -S --noconfirm jq
            else
                echo "❌ No se pudo detectar el gestor de paquetes"
                echo "💡 Instala jq manualmente o usa: https://stedolan.github.io/jq/"
                return 1
            fi
            ;;
            
        macos)
            if command -v brew &> /dev/null; then
                echo "📦 Usando Homebrew..."
                brew install jq
            elif command -v port &> /dev/null; then
                echo "📦 Usando MacPorts..."
                sudo port install jq
            else
                echo "❌ No se encontró Homebrew ni MacPorts"
                echo "💡 Instala Homebrew: https://brew.sh/"
                return 1
            fi
            ;;
            
        windows)
            echo "📦 Windows detectado..."
            if command -v choco &> /dev/null; then
                echo "📦 Usando Chocolatey..."
                choco install jq -y
            elif command -v winget &> /dev/null; then
                echo "📦 Usando winget..."
                winget install jq
            else
                echo "❌ No se encontró gestor de paquetes en Windows"
                echo "💡 Descarga jq desde: https://stedolan.github.io/jq/download/"
                echo "💡 O usa: choco install jq"
                return 1
            fi
            ;;
            
        *)
            echo "❌ Sistema no soportado: $PLATFORM"
            return 1
            ;;
    esac
    
    # Verificar instalación
    if command -v jq &> /dev/null; then
        echo "✅ jq instalado correctamente: $(jq --version)"
        return 0
    else
        echo "❌ Falló la instalación de jq"
        return 1
    fi
}


# ============================================
# MENÚ PRINCIPAL
# ============================================

show_menu() {
    print_header

    echo -e "${BOLD}${WHITE}0. ❌ Salir${NC}"
    echo ""

    echo -e "${BOLD}${WHITE}Selecciona una opción (0-10):${NC}"
    read -p "> " option
    
    case $option in
        0) 
            echo -e "${GREEN}¡Hasta luego! 🎉${NC}"
            exit 0
            ;;
        *)
            print_error "Opción inválida"
            sleep 2
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}${WHITE}Presiona Enter para continuar...${NC}"
    read
}

# ============================================
# INICIO DEL SCRIPT
# ============================================

# Verificar dependencias
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq no está instalado.${NC}"
    echo -e "${YELLOW}Instalando jq...${NC}"
    install_jq
fi

# Loop principal
while true; do
    show_menu
done
