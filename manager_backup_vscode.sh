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
# FUNCIONES DE GESTIÓN DE METADATOS
# ============================================

init_metadata() {
    if [ ! -f "$BACKUP_METADATA_FILE" ]; then
        echo '{"backups": []}' > "$BACKUP_METADATA_FILE"
    fi
}

get_backup_metadata() {
    local backup_name="$1"
    local metadata=$(cat "$BACKUP_METADATA_FILE" 2>/dev/null)
    
    if [ -z "$metadata" ]; then
        echo "null"
        return 1
    fi
    
    echo "$metadata" | jq -r ".backups[] | select(.name == \"$backup_name\")" 2>/dev/null
}

add_backup_metadata() {
    local backup_name="$1"
    local backup_type="$2"
    local description="$3"
    local backup_date="$4"
    
    local temp_file=$(mktemp)
    
    jq --arg name "$backup_name" \
       --arg type "$backup_type" \
       --arg desc "$description" \
       --arg date "$backup_date" \
       '.backups += [{"name": $name, "type": $type, "description": $desc, "date": $date}]' \
       "$BACKUP_METADATA_FILE" > "$temp_file"
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$BACKUP_METADATA_FILE"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

update_backup_metadata() {
    local backup_name="$1"
    local new_description="$2"
    
    local temp_file=$(mktemp)
    
    jq --arg name "$backup_name" \
       --arg desc "$new_description" \
       '.backups = [.backups[] | if .name == $name then .description = $desc else . end]' \
       "$BACKUP_METADATA_FILE" > "$temp_file"
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$BACKUP_METADATA_FILE"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

remove_backup_metadata() {
    local backup_name="$1"
    
    local temp_file=$(mktemp)
    
    jq --arg name "$backup_name" \
       '.backups = [.backups[] | select(.name != $name)]' \
       "$BACKUP_METADATA_FILE" > "$temp_file"
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" "$BACKUP_METADATA_FILE"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

list_backups_metadata() {
    init_metadata
    local backups=$(jq -r '.backups[] | "\(.name):\(.type):\(.description):\(.date)"' "$BACKUP_METADATA_FILE" 2>/dev/null)
    
    if [ -z "$backups" ]; then
        echo "0"
    else
        echo "$backups" | wc -l
    fi
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
# FUNCIÓN PARA OBTENER LISTA DE BACKUPS VÁLIDOS
# ============================================

get_valid_backups_list() {
    local valid_backups=()
    local backups=$(jq -r '.backups[] | "\(.name):\(.type):\(.description):\(.date)"' "$BACKUP_METADATA_FILE" 2>/dev/null)
    
    if [ -z "$backups" ]; then
        echo ""
        return
    fi
    
    while IFS=: read -r name type desc date; do
        # Ignorar el directorio base y backups que no sean válidos
        if [ "$name" = "vscode_backups" ] || [ "$name" = "backups" ]; then
            continue
        fi
        
        local backup_dir="$BACKUP_BASE_DIR/$name"
        if [ -d "$backup_dir" ]; then
            # Verificar que el directorio contenga al menos un subdirectorio válido
            local has_content=false
            if [ -d "$backup_dir/config" ] || [ -d "$backup_dir/extensions" ] || [ -d "$backup_dir/cache" ]; then
                has_content=true
            fi
            
            # Si no tiene contenido, verificar si tiene otros archivos/directorios
            if [ "$has_content" = false ]; then
                local file_count=$(find "$backup_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
                local dir_count=$(find "$backup_dir" -maxdepth 1 -type d ! -path "$backup_dir" 2>/dev/null | wc -l)
                if [ "$file_count" -gt 0 ] || [ "$dir_count" -gt 0 ]; then
                    has_content=true
                fi
            fi
            
            if [ "$has_content" = true ]; then
                valid_backups+=("$name")
            fi
        fi
    done <<< "$backups"
    
    # Imprimir los nombres separados por espacio
    echo "${valid_backups[@]}"
}

# ============================================
# FUNCIÓN PARA RESTABLECER VS CODE A ESTADO DE FÁBRICA
# ============================================

reset_vscode_factory() {
    print_header
    echo -e "${BOLD}🔄 RESTABLECER VS CODE A ESTADO DE FÁBRICA${NC}"
    echo ""
    
    # Verificar VS Code
    check_vscode || return 1
    
    echo ""
    print_separator
    echo -e "${BOLD}${RED}⚠️  ¡ADVERTENCIA! Este script ELIMINARÁ PERMANENTEMENTE:${NC}"
    echo -e "  ${RED}• Todas tus configuraciones de VS Code (settings.json, keybindings, etc.)${NC}"
    echo -e "  ${RED}• Todas las extensiones instaladas${NC}"
    echo -e "  ${RED}• La caché de VS Code${NC}"
    print_separator
    echo ""
    
    echo -e "${BOLD}${RED}¿Estás seguro de que quieres continuar? (escribe 'SI' para confirmar):${NC}"
    read -p "> " confirm_reset
    
    if [ "$confirm_reset" != "SI" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    print_info "Preparando el proceso de limpieza..."
    echo ""
    
    # Crear backup automático antes de resetear
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="factory_reset_backup_${timestamp}"
    local backup_dir="$BACKUP_BASE_DIR/$backup_name"
    
    print_info "Creando carpeta de backup en: $backup_dir"
    mkdir -p "$backup_dir"
    
    # Respaldar configuraciones
    if [ -d "$VSCODE_USER_DIR" ]; then
        print_info "Respaldando configuraciones..."
        mkdir -p "$backup_dir/config"
        cp -r "$VSCODE_USER_DIR" "$backup_dir/config/"
        print_success "Configuraciones respaldadas"
    else
        print_warning "No se encontraron configuraciones para respaldar"
    fi
    
    # Respaldar extensiones
    if [ -d "$VSCODE_EXTENSIONS_DIR" ]; then
        print_info "Respaldando extensiones..."
        mkdir -p "$backup_dir/extensions"
        cp -r "$VSCODE_EXTENSIONS_DIR" "$backup_dir/"
        print_success "Extensiones respaldadas"
    else
        print_warning "No se encontraron extensiones para respaldar"
    fi
    
    # Respaldar caché
    if [ -d "$VSCODE_CACHE_DIR" ]; then
        print_info "Respaldando caché..."
        mkdir -p "$backup_dir/cache"
        cp -r "$VSCODE_CACHE_DIR" "$backup_dir/"
        print_success "Caché respaldada"
    else
        print_warning "No se encontró caché para respaldar"
    fi
    
    # Guardar metadatos del backup de fábrica
    if add_backup_metadata "$backup_name" "factory_reset" "Backup automático antes de resetear a fábrica" "$timestamp"; then
        print_success "Metadatos del backup guardados"
    fi
    
    echo ""
    print_success "Backup creado en: $backup_dir"
    echo ""
    
    echo -e "${BOLD}${WHITE}¿Continuar con la eliminación de datos? (s/N):${NC}"
    read -p "> " continue_reset
    
    if [[ ! "$continue_reset" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada. El backup se mantiene en: $backup_dir"
        return 0
    fi
    
    echo ""
    print_info "Iniciando limpieza de VS Code..."
    echo ""
    
    # Eliminar configuraciones
    if [ -d "$HOME/.config/Code" ]; then
        print_info "Eliminando configuraciones principales..."
        rm -rf "$HOME/.config/Code"
        print_success "Configuraciones eliminadas"
    else
        print_warning "No se encontraron configuraciones para eliminar"
    fi
    
    # Eliminar extensiones
    if [ -d "$HOME/.vscode" ]; then
        print_info "Eliminando extensiones instaladas..."
        rm -rf "$HOME/.vscode"
        print_success "Extensiones eliminadas"
    else
        print_warning "No se encontraron extensiones para eliminar"
    fi
    
    # Eliminar caché
    if [ -d "$HOME/.cache/vscode-cpptools" ]; then
        print_info "Eliminando caché..."
        rm -rf "$HOME/.cache/vscode-cpptools"
        print_success "Caché eliminada"
    else
        print_warning "No se encontró caché en ~/.cache/Code"
    fi
    
    # Eliminar otros archivos de caché de VS Code
    local cache_dirs=(
        "$HOME/.cache/Code"
        "$HOME/.cache/vscode"
        "$HOME/.config/Code/CachedData"
        "$HOME/.config/Code/CachedExtensions"
        "$HOME/.config/Code/Code Cache"
    )
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            print_info "Eliminando: $cache_dir"
            rm -rf "$cache_dir"
        fi
    done
    
    echo ""
    print_success "¡Limpieza completada con éxito!"
    echo ""
    print_success "¡VS Code ha sido restablecido a estado de fábrica!"
    print_info "Al abrir VS Code, se iniciará como si fuera una instalación nueva."
    echo ""
    print_info "El backup se encuentra en: $backup_dir"
    print_info "Si todo funciona bien, puedes eliminar esa carpeta manualmente."
    echo ""
    
    echo -e "${BOLD}${WHITE}¿Quieres eliminar la carpeta de backup ahora? (s/N):${NC}"
    read -p "> " delete_backup
    
    if [[ "$delete_backup" =~ ^[Ss]$ ]]; then
        rm -rf "$backup_dir"
        remove_backup_metadata "$backup_name"
        print_success "Carpeta de backup eliminada"
    else
        print_info "La carpeta de backup se mantiene en: $backup_dir"
        print_info "Puedes eliminarla manualmente cuando quieras"
    fi
    
    echo ""
    echo -e "${BOLD}${WHITE}¿Quieres abrir VS Code ahora? (s/N):${NC}"
    read -p "> " open_vscode
    
    if [[ "$open_vscode" =~ ^[Ss]$ ]]; then
        code &
        print_success "VS Code iniciado"
    fi
    
    echo ""
    print_success "¡Proceso completado! 🎉"
}


# ============================================
# FUNCIONES PRINCIPALES
# ============================================

create_backup() {
    print_header
    echo -e "${BOLD}📦 CREAR BACKUP${NC}"
    echo ""
    
    # Verificar VS Code
    check_vscode || return 1
    
    # Verificar directorios
    if [ ! -d "$VSCODE_USER_DIR" ]; then
        print_error "No se encontró el directorio de configuración de VS Code"
        return 1
    fi
    
    # Preguntar nombre del backup
    echo -e "${BOLD}${WHITE}Nombre del backup (ej. nestjs_backup, react_backup) [0 para cancelar]:${NC}"
    read -p "> " backup_name
    
    if [ "$backup_name" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if [ -z "$backup_name" ]; then
        print_error "El nombre no puede estar vacío"
        return 1
    fi
    
    # Sanitizar nombre y obtener timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    backup_name=$(echo "$backup_name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    backup_name="${backup_name}_${timestamp}"
    
    local backup_dir="$BACKUP_BASE_DIR/$backup_name"
    
    if [ -d "$backup_dir" ]; then
        print_error "Ya existe un backup con ese nombre"
        return 1
    fi
    
    # Preguntar descripción
    echo -e "${BOLD}${WHITE}Descripción del backup (opcional) [0 para cancelar]:${NC}"
    read -p "> " backup_description
    
    if [ "$backup_description" = "0" ]; then
        print_info "Operación cancelada"
        rm -rf "$backup_dir"
        return 0
    fi
    
    # Crear directorio del backup
    mkdir -p "$backup_dir"
    
    # Seleccionar qué respaldar
    echo ""
    echo -e "${BOLD}${WHITE}¿Qué deseas respaldar? [0 para cancelar]${NC}"
    echo "1) Todo (configuraciones, extensiones y caché)"
    echo "2) Solo configuraciones"
    echo "3) Solo extensiones"
    echo "4) Solo caché"
    echo "5) Configuraciones y extensiones"
    echo "6) Configuraciones y caché"
    echo "7) Extensiones y caché"
    echo ""
    read -p "Selecciona una opción (0-7): " backup_option
    
    if [ "$backup_option" = "0" ]; then
        print_info "Operación cancelada"
        rm -rf "$backup_dir"
        return 0
    fi
    
    local backup_config=false
    local backup_extensions=false
    local backup_cache=false
    
    case $backup_option in
        1) backup_config=true; backup_extensions=true; backup_cache=true ;;
        2) backup_config=true ;;
        3) backup_extensions=true ;;
        4) backup_cache=true ;;
        5) backup_config=true; backup_extensions=true ;;
        6) backup_config=true; backup_cache=true ;;
        7) backup_extensions=true; backup_cache=true ;;
        *) print_error "Opción inválida"; rm -rf "$backup_dir"; return 1 ;;
    esac
    
    # Realizar backup
    print_info "Creando backup en: $backup_dir"
    
    if [ "$backup_config" = true ]; then
        print_info "Respaldando configuraciones..."
        mkdir -p "$backup_dir/config"
        cp -r "$VSCODE_USER_DIR" "$backup_dir/config/"
        print_success "Configuraciones respaldadas"
    fi
    
    if [ "$backup_extensions" = true ]; then
        print_info "Respaldando extensiones..."
        if [ -d "$VSCODE_EXTENSIONS_DIR" ]; then
            mkdir -p "$backup_dir/extensions"
            cp -r "$VSCODE_EXTENSIONS_DIR" "$backup_dir/"
            print_success "Extensiones respaldadas"
        else
            print_warning "No se encontraron extensiones"
        fi
    fi
    
    if [ "$backup_cache" = true ]; then
        print_info "Respaldando caché..."
        if [ -d "$VSCODE_CACHE_DIR" ]; then
            mkdir -p "$backup_dir/cache"
            cp -r "$VSCODE_CACHE_DIR" "$backup_dir/"
            print_success "Caché respaldada"
        else
            print_warning "No se encontró caché"
        fi
    fi
    
    # Guardar metadatos
    if add_backup_metadata "$backup_name" "manual" "$backup_description" "$timestamp"; then
        print_success "Metadatos guardados correctamente"
    else
        print_error "Error al guardar metadatos"
    fi
    
    # Mostrar información del backup
    local backup_size=$(get_backup_size "$backup_dir")
    echo ""
    print_success "Backup creado exitosamente: $backup_name"
    print_info "Tamaño: $backup_size"
    print_info "Ubicación: $backup_dir"
}

restore_backup() {
    print_header
    echo -e "${BOLD}🔄 RESTAURAR BACKUP${NC}"
    echo ""
    
    # Verificar VS Code
    check_vscode || return 1
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 1
    fi
    
    # Mostrar backups con índice y descripción
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        # Mostrar descripción si existe
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        
        ((index++))
    done
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No se encontraron backups válidos"
        return 1
    fi
    
    # Seleccionar backup
    echo -e "${BOLD}${WHITE}Selecciona el número del backup a restaurar (0 para salir):${NC}"
    read -p "> " selection
    
    if [ "$selection" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local selected_backup="${backup_names[$((selection-1))]}"
    local backup_dir="$BACKUP_BASE_DIR/$selected_backup"
    
    print_info "Backup seleccionado: $selected_backup"
    print_info "Ruta: $backup_dir"
    
    # Confirmar restauración
    echo ""
    echo -e "${BOLD}${WHITE}¿Restaurar este backup? (s/N):${NC}"
    read -p "> " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    print_info "Iniciando restauración desde: $selected_backup"
    
    # Verificar contenido del backup
    local check_dirs=$(check_backup_dirs "$backup_dir")
    local has_config=$(echo "$check_dirs" | cut -d':' -f1)
    local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
    local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
    
    if [ "$has_config" = "false" ] && [ "$has_extensions" = "false" ] && [ "$has_cache" = "false" ]; then
        print_error "El backup no contiene datos válidos"
        return 1
    fi
    
    # Seleccionar qué restaurar
    echo ""
    echo -e "${BOLD}${WHITE}¿Qué deseas restaurar? [0 para cancelar]${NC}"
    echo "1) Todo (configuraciones, extensiones y caché)"
    echo "2) Solo configuraciones"
    echo "3) Solo extensiones"
    echo "4) Solo caché"
    echo "5) Configuraciones y extensiones"
    echo "6) Configuraciones y caché"
    echo "7) Extensiones y caché"
    echo ""
    read -p "Selecciona una opción (0-7): " restore_option
    
    if [ "$restore_option" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    local restore_config=false
    local restore_extensions=false
    local restore_cache=false
    
    case $restore_option in
        1) restore_config=true; restore_extensions=true; restore_cache=true ;;
        2) restore_config=true ;;
        3) restore_extensions=true ;;
        4) restore_cache=true ;;
        5) restore_config=true; restore_extensions=true ;;
        6) restore_config=true; restore_cache=true ;;
        7) restore_extensions=true; restore_cache=true ;;
        *) print_error "Opción inválida"; return 1 ;;
    esac
    
    # Realizar restauración
    if [ "$restore_config" = true ] && [ "$has_config" = "true" ]; then
        print_info "Restaurando configuraciones..."
        if [ -d "$HOME/.config/Code" ]; then
            # Crear backup del config actual
            local temp_config_backup="$BACKUP_BASE_DIR/temp_config_$(date +%Y%m%d_%H%M%S)"
            cp -r "$HOME/.config/Code" "$temp_config_backup"
            print_info "Backup temporal de configuración creado en: $temp_config_backup"
        fi
        
        # Restaurar configuración
        mkdir -p "$HOME/.config"
        cp -r "$backup_dir/config/Code" "$HOME/.config/"
        print_success "Configuraciones restauradas"
    fi
    
    if [ "$restore_extensions" = true ] && [ "$has_extensions" = "true" ]; then
        print_info "Restaurando extensiones..."
        if [ -d "$HOME/.vscode" ]; then
            # Crear backup del extensions actual
            local temp_ext_backup="$BACKUP_BASE_DIR/temp_extensions_$(date +%Y%m%d_%H%M%S)"
            cp -r "$HOME/.vscode" "$temp_ext_backup"
            print_info "Backup temporal de extensiones creado en: $temp_ext_backup"
        fi
        
        # Restaurar extensiones
        mkdir -p "$HOME/.vscode"
        cp -r "$backup_dir/extensions" "$HOME/.vscode/"
        print_success "Extensiones restauradas"
    fi
    
    if [ "$restore_cache" = true ] && [ "$has_cache" = "true" ]; then
        print_info "Restaurando caché..."
        mkdir -p "$HOME/.cache"
        cp -r "$backup_dir/cache" "$HOME/.cache/"
        print_success "Caché restaurada"
    fi
    
    echo ""
    print_success "¡Restauración completada con éxito!"
    print_info "Para que los cambios surtan efecto, reinicia VS Code"
    print_info "Si no funciona correctamente, puedes eliminar los archivos restaurados y volver a intentarlo"
    
    echo ""
    echo -e "${BOLD}${WHITE}¿Quieres abrir VS Code ahora? (s/N):${NC}"
    read -p "> " open_vscode
    
    if [[ "$open_vscode" =~ ^[Ss]$ ]]; then
        code &
        print_success "VS Code iniciado"
    fi
}

list_backups() {
    print_header
    echo -e "${BOLD}📋 LISTAR BACKUPS${NC}"
    echo ""
    
    init_metadata
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 0
    fi
    
    echo -e "${BOLD}${WHITE}Backups disponibles: $backup_count${NC}"
    echo "===================="
    echo ""
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}[$index]${NC} ${BOLD}$name${NC}"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
}

delete_backup() {
    print_header
    echo -e "${BOLD}🗑️ ELIMINAR BACKUP${NC}"
    echo ""
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 0
    fi
    
    # Mostrar backups con índice
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
    
    echo -e "${BOLD}${WHITE}Selecciona el número del backup a eliminar (0 para salir):${NC}"
    read -p "> " selection
    
    if [ "$selection" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local selected_backup="${backup_names[$((selection-1))]}"
    
    echo -e "${BOLD}${WHITE}¿Estás seguro de eliminar el backup '$selected_backup'? (s/N):${NC}"
    read -p "> " confirm
    
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    # Eliminar directorio y metadatos
    local backup_dir="$BACKUP_BASE_DIR/$selected_backup"
    if [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
        print_success "Directorio eliminado: $backup_dir"
    fi
    
    if remove_backup_metadata "$selected_backup"; then
        print_success "Metadatos eliminados para: $selected_backup"
    else
        print_warning "No se pudieron eliminar los metadatos para: $selected_backup"
    fi
    
    print_success "Backup eliminado: $selected_backup"
}

edit_metadata() {
    print_header
    echo -e "${BOLD}✏️ EDITAR METADATOS${NC}"
    echo ""
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 0
    fi
    
    # Mostrar backups con índice
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
    
    echo -e "${BOLD}${WHITE}Selecciona el número del backup a editar (0 para salir):${NC}"
    read -p "> " selection
    
    if [ "$selection" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local selected_backup="${backup_names[$((selection-1))]}"
    
    local current_desc=$(get_backup_metadata "$selected_backup" | jq -r '.description')
    
    echo -e "${BOLD}${WHITE}Descripción actual:${NC} $current_desc"
    echo -e "${BOLD}${WHITE}Nueva descripción (dejar vacío para mantener la actual) [0 para cancelar]:${NC}"
    read -p "> " new_description
    
    if [ "$new_description" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if [ -n "$new_description" ]; then
        if update_backup_metadata "$selected_backup" "$new_description"; then
            print_success "Metadatos actualizados para: $selected_backup"
        else
            print_error "Error al actualizar metadatos"
        fi
    else
        print_info "No se realizaron cambios"
    fi
}

duplicate_backup() {
    print_header
    echo -e "${BOLD}📋 DUPLICAR BACKUP${NC}"
    echo ""
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 0
    fi
    
    # Mostrar backups con índice
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
    
    echo -e "${BOLD}${WHITE}Selecciona el número del backup a duplicar (0 para salir):${NC}"
    read -p "> " selection
    
    if [ "$selection" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local source_name="${backup_names[$((selection-1))]}"
    local source_dir="$BACKUP_BASE_DIR/$source_name"
    
    if [ ! -d "$source_dir" ]; then
        print_error "El directorio del backup no existe"
        return 1
    fi
    
    echo -e "${BOLD}${WHITE}Nombre para el nuevo backup (opcional) [0 para cancelar]:${NC}"
    read -p "> " new_name
    
    if [ "$new_name" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if [ -z "$new_name" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        new_name="${source_name}_copy_${timestamp}"
    fi
    
    # Sanitizar nombre
    new_name=$(echo "$new_name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    
    local dest_dir="$BACKUP_BASE_DIR/$new_name"
    
    if [ -d "$dest_dir" ]; then
        print_error "Ya existe un backup con ese nombre"
        return 1
    fi
    
    # Copiar directorio
    cp -r "$source_dir" "$dest_dir"
    
    # Obtener metadatos del source
    local source_metadata=$(get_backup_metadata "$source_name")
    local source_type=$(echo "$source_metadata" | jq -r '.type')
    local source_desc=$(echo "$source_metadata" | jq -r '.description')
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Agregar metadatos
    if add_backup_metadata "$new_name" "$source_type" "Copia de: $source_name - $source_desc" "$timestamp"; then
        print_success "Backup duplicado: $new_name"
    else
        print_error "Error al duplicar backup"
        rm -rf "$dest_dir"
        return 1
    fi
}

compare_backups() {
    print_header
    echo -e "${BOLD}🔍 COMPARAR BACKUPS${NC}"
    echo ""
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -lt 2 ]; then
        print_warning "Se necesitan al menos 2 backups para comparar"
        return 0
    fi
    
    # Mostrar backups con índice
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
    
    echo -e "${BOLD}${WHITE}Selecciona el primer backup (0 para salir):${NC}"
    read -p "> " selection1
    
    if [ "$selection1" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    echo -e "${BOLD}${WHITE}Selecciona el segundo backup (0 para salir):${NC}"
    read -p "> " selection2
    
    if [ "$selection2" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection1" =~ ^[0-9]+$ ]] || [ "$selection1" -lt 1 ] || [ "$selection1" -gt $backup_count ] || \
       ! [[ "$selection2" =~ ^[0-9]+$ ]] || [ "$selection2" -lt 1 ] || [ "$selection2" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local backup1_name="${backup_names[$((selection1-1))]}"
    local backup2_name="${backup_names[$((selection2-1))]}"
    
    local backup1_dir="$BACKUP_BASE_DIR/$backup1_name"
    local backup2_dir="$BACKUP_BASE_DIR/$backup2_name"
    
    echo ""
    echo -e "${BOLD}${WHITE}Comparando:${NC}"
    echo -e "1) $backup1_name"
    echo -e "2) $backup2_name"
    echo ""
    
    # Comparar tamaños
    local size1=$(get_backup_size "$backup1_dir")
    local size2=$(get_backup_size "$backup2_dir")
    echo -e "${BOLD}Tamaño:${NC}"
    echo -e "  $backup1_name: $size1"
    echo -e "  $backup2_name: $size2"
    echo ""
    
    # Comparar contenido
    local check1=$(check_backup_dirs "$backup1_dir")
    local check2=$(check_backup_dirs "$backup2_dir")
    
    local has_config1=$(echo "$check1" | cut -d':' -f1)
    local has_extensions1=$(echo "$check1" | cut -d':' -f2)
    local has_cache1=$(echo "$check1" | cut -d':' -f3)
    
    local has_config2=$(echo "$check2" | cut -d':' -f1)
    local has_extensions2=$(echo "$check2" | cut -d':' -f2)
    local has_cache2=$(echo "$check2" | cut -d':' -f3)
    
    echo -e "${BOLD}Contenido:${NC}"
    echo -e "  $backup1_name: Config[$([ "$has_config1" = "true" ] && echo "✓" || echo "✗")] Extensions[$([ "$has_extensions1" = "true" ] && echo "✓" || echo "✗")] Cache[$([ "$has_cache1" = "true" ] && echo "✓" || echo "✗")]"
    echo -e "  $backup2_name: Config[$([ "$has_config2" = "true" ] && echo "✓" || echo "✗")] Extensions[$([ "$has_extensions2" = "true" ] && echo "✓" || echo "✗")] Cache[$([ "$has_cache2" = "true" ] && echo "✓" || echo "✗")]"
    echo ""
    
    # Contar archivos
    local files1=$(find "$backup1_dir" -type f 2>/dev/null | wc -l)
    local files2=$(find "$backup2_dir" -type f 2>/dev/null | wc -l)
    
    echo -e "${BOLD}Archivos:${NC}"
    echo -e "  $backup1_name: $files1 archivos"
    echo -e "  $backup2_name: $files2 archivos"
}

export_backup() {
    print_header
    echo -e "${BOLD}📤 EXPORTAR BACKUP${NC}"
    echo ""
    
    # Obtener la lista de backups válidos
    local backup_names=($(get_valid_backups_list))
    local backup_count=${#backup_names[@]}
    
    if [ $backup_count -eq 0 ]; then
        print_warning "No hay backups disponibles"
        return 0
    fi
    
    # Mostrar backups con índice
    echo -e "${BOLD}${WHITE}Backups disponibles:${NC}"
    echo "===================="
    
    local index=1
    for name in "${backup_names[@]}"; do
        local backup_dir="$BACKUP_BASE_DIR/$name"
        local size=$(get_backup_size "$backup_dir")
        local check_dirs=$(check_backup_dirs "$backup_dir")
        local has_config=$(echo "$check_dirs" | cut -d':' -f1)
        local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
        local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
        
        local config_status="✗"
        local ext_status="✗"
        local cache_status="✗"
        
        [ "$has_config" = "true" ] && config_status="✓"
        [ "$has_extensions" = "true" ] && ext_status="✓"
        [ "$has_cache" = "true" ] && cache_status="✓"
        
        # Obtener metadatos
        local metadata=$(get_backup_metadata "$name")
        local date_raw=$(echo "$metadata" | jq -r '.date')
        local desc=$(echo "$metadata" | jq -r '.description')
        
        # Formatear fecha
        local date_formatted=$(format_date "$date_raw")
        
        echo -e "${GREEN}$index)${NC} $name"
        echo -e "   📅 Fecha: $date_formatted"
        echo -e "   📦 Tamaño: $size"
        echo -e "   📁 Contiene: Config[$config_status] Extensions[$ext_status] Cache[$cache_status]"
        if [ -n "$desc" ] && [ "$desc" != "null" ]; then
            echo -e "   📝 Descripción: $desc"
        fi
        echo ""
        ((index++))
    done
    
    echo -e "${BOLD}${WHITE}Selecciona el número del backup a exportar (0 para salir):${NC}"
    read -p "> " selection
    
    if [ "$selection" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt $backup_count ]; then
        print_error "Selección inválida"
        return 1
    fi
    
    local selected_backup="${backup_names[$((selection-1))]}"
    local backup_dir="$BACKUP_BASE_DIR/$selected_backup"
    
    if [ ! -d "$backup_dir" ]; then
        print_error "El directorio del backup no existe"
        return 1
    fi
    
    echo ""
    echo -e "${BOLD}${WHITE}Ubicación para exportar:${NC}"
    echo -e "  ${YELLOW}Nota:${NC} Puedes especificar una ruta completa o solo el nombre del archivo"
    echo -e "  ${YELLOW}Ejemplos:${NC}"
    echo -e "    /home/usuario/backup.tar.gz"
    echo -e "    ~/backups/mi_backup.tar.gz"
    echo -e "    mi_backup.tar.gz (se guardará en el directorio actual)"
    echo -e "  ${YELLOW}[0 para cancelar]${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}Ruta de exportación (presiona Enter para usar el directorio actual):${NC}"
    read -p "> " export_path
    
    if [ "$export_path" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    # Si no se especificó ruta, usar el directorio actual
    if [ -z "$export_path" ]; then
        export_path="./${selected_backup}.tar.gz"
    fi
    
    # Expandir ~ si existe
    export_path=$(echo "$export_path" | sed "s|~|$HOME|g")
    
    # Verificar si la ruta es un directorio existente
    if [ -d "$export_path" ]; then
        print_error "La ruta especificada es un directorio, no un archivo"
        echo -e "${YELLOW}¿Deseas exportar dentro de este directorio? (s/N):${NC}"
        read -p "> " use_dir
        
        if [[ "$use_dir" =~ ^[Ss]$ ]]; then
            # Agregar el nombre del archivo al directorio
            if [[ "$export_path" != */ ]]; then
                export_path="${export_path}/"
            fi
            export_path="${export_path}${selected_backup}.tar.gz"
            print_info "Exportando a: $export_path"
        else
            print_info "Operación cancelada"
            return 0
        fi
    fi
    
    # Verificar que la ruta no sea un directorio
    if [ -d "$export_path" ]; then
        print_error "La ruta especificada es un directorio. Por favor, especifica un nombre de archivo."
        return 1
    fi
    
    # Verificar que tenga extensión .tar.gz, si no, agregarla
    if [[ ! "$export_path" =~ \.tar\.gz$ ]]; then
        export_path="${export_path}.tar.gz"
        print_info "Extensión .tar.gz agregada automáticamente"
    fi
    
    # Crear el directorio padre si no existe
    local export_dir=$(dirname "$export_path")
    if [ ! -d "$export_dir" ]; then
        print_info "Creando directorio: $export_dir"
        mkdir -p "$export_dir"
        if [ $? -ne 0 ]; then
            print_error "No se pudo crear el directorio: $export_dir"
            return 1
        fi
    fi
    
    # Verificar si el archivo ya existe
    if [ -f "$export_path" ]; then
        echo -e "${YELLOW}El archivo ya existe. ¿Sobrescribir? (s/N):${NC}"
        read -p "> " overwrite
        if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    fi
    
    # Crear archivo comprimido
    print_info "Exportando backup a: $export_path"
    
    # Crear un archivo temporal para el tar
    local temp_tar=$(mktemp)
    
    # Comprimir el backup
    tar -czf "$temp_tar" -C "$BACKUP_BASE_DIR" "$selected_backup" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Mover el archivo temporal a la ubicación final
        mv "$temp_tar" "$export_path"
        
        if [ $? -eq 0 ]; then
            local export_size=$(du -sh "$export_path" 2>/dev/null | cut -f1)
            echo ""
            print_success "Backup exportado exitosamente"
            print_info "Tamaño: $export_size"
            print_info "Ubicación: $export_path"
            
            # Preguntar si quiere ver el contenido
            echo ""
            echo -e "${BOLD}${WHITE}¿Quieres ver el contenido del archivo exportado? (s/N):${NC}"
            read -p "> " view_content
            if [[ "$view_content" =~ ^[Ss]$ ]]; then
                tar -tzf "$export_path" | head -20
                echo -e "${YELLOW}... (mostrando primeros 20 archivos)${NC}"
            fi
        else
            print_error "Error al mover el archivo exportado"
            rm -f "$temp_tar"
            return 1
        fi
    else
        print_error "Error al exportar el backup"
        rm -f "$temp_tar"
        return 1
    fi
}


import_backup() {
    print_header
    echo -e "${BOLD}📥 IMPORTAR BACKUP${NC}"
    echo ""
    
    echo -e "${BOLD}${WHITE}Ruta del archivo de backup a importar (.tar.gz) [0 para cancelar]:${NC}"
    read -p "> " import_path
    
    if [ "$import_path" = "0" ]; then
        print_info "Operación cancelada"
        return 0
    fi
    
    # Expandir ~ si existe
    import_path=$(echo "$import_path" | sed "s|~|$HOME|g")
    
    if [ ! -f "$import_path" ]; then
        print_error "El archivo no existe: $import_path"
        return 1
    fi
    
    if [[ ! "$import_path" =~ \.tar\.gz$ ]]; then
        print_warning "El archivo no tiene extensión .tar.gz, pero se intentará importar"
    fi
    
    # Verificar que el archivo es un tar.gz válido
    print_info "Verificando archivo..."
    if ! tar -tzf "$import_path" >/dev/null 2>&1; then
        print_error "El archivo no es un tar.gz válido o está corrupto"
        return 1
    fi
    
    # Listar el contenido para ver la estructura
    print_info "Analizando estructura del archivo..."
    local first_level=$(tar -tzf "$import_path" 2>/dev/null | head -1 | cut -d'/' -f1)
    
    if [ -z "$first_level" ]; then
        print_error "El archivo está vacío o no contiene datos"
        return 1
    fi
    
    print_info "Estructura detectada: $first_level"
    
    # El nombre del backup se extrae del primer nivel del tar
    local original_name="$first_level"
    local backup_name="$original_name"
    
    # Verificar si ya existe
    if [ -d "$BACKUP_BASE_DIR/$backup_name" ]; then
        print_warning "Ya existe un backup con el nombre: $backup_name"
        echo -e "${BOLD}${WHITE}¿Deseas sobrescribirlo o importar con otro nombre?${NC}"
        echo "1) Sobrescribir"
        echo "2) Importar con otro nombre"
        echo "3) Cancelar"
        read -p "Selecciona una opción (1-3): " import_option
        
        case $import_option in
            1)
                print_info "Sobrescribiendo backup existente..."
                rm -rf "$BACKUP_BASE_DIR/$backup_name"
                remove_backup_metadata "$backup_name"
                ;;
            2)
                echo -e "${BOLD}${WHITE}Ingresa un nuevo nombre para el backup:${NC}"
                read -p "> " new_name
                if [ -z "$new_name" ]; then
                    print_error "El nombre no puede estar vacío"
                    return 1
                fi
                # Sanitizar nombre y agregar timestamp si no lo tiene
                new_name=$(echo "$new_name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
                # Verificar si el nombre ya tiene timestamp
                if [[ ! "$new_name" =~ _[0-9]{8}_[0-9]{6}$ ]]; then
                    local timestamp=$(date +%Y%m%d_%H%M%S)
                    backup_name="${new_name}_${timestamp}"
                else
                    backup_name="$new_name"
                fi
                ;;
            3|*)
                print_info "Operación cancelada"
                return 0
                ;;
        esac
    fi
    
    # Crear un directorio temporal para extraer el archivo
    local temp_dir=$(mktemp -d)
    
    # Extraer archivo en el directorio temporal
    print_info "Extrayendo archivo en directorio temporal..."
    tar -xzf "$import_path" -C "$temp_dir"
    
    if [ $? -ne 0 ]; then
        print_error "Error al extraer el archivo"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verificar que el directorio extraído existe
    local extracted_dir="$temp_dir/$original_name"
    if [ ! -d "$extracted_dir" ]; then
        print_error "No se encontró el directorio esperado: $original_name"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Si el nombre es diferente, renombrar el directorio
    if [ "$backup_name" != "$original_name" ]; then
        print_info "Renombrando backup de '$original_name' a '$backup_name'"
        mv "$extracted_dir" "$temp_dir/$backup_name"
        extracted_dir="$temp_dir/$backup_name"
    fi
    
    # Verificar si ya existe el backup en el destino
    local dest_dir="$BACKUP_BASE_DIR/$backup_name"
    if [ -d "$dest_dir" ]; then
        print_warning "El directorio destino ya existe: $dest_dir"
        echo -e "${BOLD}${WHITE}¿Deseas sobrescribirlo? (s/N):${NC}"
        read -p "> " overwrite
        if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            rm -rf "$temp_dir"
            return 0
        fi
        rm -rf "$dest_dir"
        remove_backup_metadata "$backup_name"
    fi
    
    # Mover el directorio al destino final
    print_info "Moviendo backup a: $BACKUP_BASE_DIR"
    mv "$extracted_dir" "$BACKUP_BASE_DIR/"
    
    if [ $? -ne 0 ]; then
        print_error "Error al mover el backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Limpiar directorio temporal
    rm -rf "$temp_dir"
    
    # Verificar que el backup se movió correctamente
    if [ ! -d "$BACKUP_BASE_DIR/$backup_name" ]; then
        print_error "Error: El backup no se movió correctamente"
        return 1
    fi
    
    # Verificar si el backup tiene contenido válido
    local check_dirs=$(check_backup_dirs "$BACKUP_BASE_DIR/$backup_name")
    local has_config=$(echo "$check_dirs" | cut -d':' -f1)
    local has_extensions=$(echo "$check_dirs" | cut -d':' -f2)
    local has_cache=$(echo "$check_dirs" | cut -d':' -f3)
    
    if [ "$has_config" = "false" ] && [ "$has_extensions" = "false" ] && [ "$has_cache" = "false" ]; then
        print_warning "El backup importado no contiene configuraciones, extensiones o caché válidos"
        echo -e "${YELLOW}¿Deseas mantenerlo de todos modos? (s/N):${NC}"
        read -p "> " keep_backup
        if [[ ! "$keep_backup" =~ ^[Ss]$ ]]; then
            rm -rf "$BACKUP_BASE_DIR/$backup_name"
            print_info "Backup eliminado"
            return 0
        fi
    fi
    
    # Extraer fecha del nombre del backup
    local date_part=$(echo "$backup_name" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
    if [ -z "$date_part" ]; then
        date_part=$(date +%Y%m%d_%H%M%S)
    fi
    
    # Agregar metadatos
    local description="Importado desde: $(basename "$import_path")"
    if add_backup_metadata "$backup_name" "imported" "$description" "$date_part"; then
        local backup_size=$(get_backup_size "$BACKUP_BASE_DIR/$backup_name")
        echo ""
        print_success "Backup importado exitosamente: $backup_name"
        print_info "Tamaño: $backup_size"
        print_info "Ubicación: $BACKUP_BASE_DIR/$backup_name"
        print_info "Contenido: Config[$([ "$has_config" = "true" ] && echo "✓" || echo "✗")] Extensions[$([ "$has_extensions" = "true" ] && echo "✓" || echo "✗")] Cache[$([ "$has_cache" = "true" ] && echo "✓" || echo "✗")]"
        
        # Mostrar los directorios creados
        echo ""
        echo -e "${BOLD}${WHITE}Estructura del backup importado:${NC}"
        ls -la "$BACKUP_BASE_DIR/$backup_name" | grep -E '^d' | awk '{print "  📁 " $9}'
    else
        print_error "Error al guardar metadatos del backup importado"
        rm -rf "$BACKUP_BASE_DIR/$backup_name"
        return 1
    fi
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_menu() {
    print_header

    echo -e "${BOLD}${WHITE}1. 📦 Crear backup${NC}"
    echo -e "${BOLD}${WHITE}2. 🔄 Restaurar backup${NC}"
    echo -e "${BOLD}${WHITE}3. 📋 Listar backups${NC}"
    echo -e "${BOLD}${WHITE}4. 🗑️ Eliminar backup${NC}"
    echo -e "${BOLD}${WHITE}5. ✏️ Editar metadatos${NC}"
    echo -e "${BOLD}${WHITE}6. 📋 Duplicar backup${NC}"
    echo -e "${BOLD}${WHITE}7. 🔍 Comparar backups${NC}"
    echo -e "${BOLD}${WHITE}8. 📤 Exportar backup${NC}"
    echo -e "${BOLD}${WHITE}9. 📥 Importar backup${NC}"
    echo -e "${BOLD}${WHITE}10. 🔄 Restablecer VS Code a estado de fábrica${NC}"
    echo -e "${BOLD}${WHITE}0. ❌ Salir${NC}"
    echo ""

    local backup_count=$(list_backups_metadata)
    echo -e "Backups disponibles: ${GREEN}$backup_count${NC}"
    echo ""

    echo -e "${BOLD}${WHITE}Selecciona una opción (0-10):${NC}"
    read -p "> " option
    
    case $option in
        1) create_backup ;;
        2) restore_backup ;;
        3) list_backups ;;
        4) delete_backup ;;
        5) edit_metadata ;;
        6) duplicate_backup ;;
        7) compare_backups ;;
        8) export_backup ;;
        9) import_backup ;;
        10) reset_vscode_factory ;;
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
# RECUPERAR BACKUPS EXISTENTES
# ============================================

recover_existing_backups() {
    init_metadata
    
    # Buscar directorios de backup que no estén en metadata
    local existing_backups=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d ! -path "$BACKUP_BASE_DIR" | while read dir; do
        local name=$(basename "$dir")
        
        # Ignorar directorios que no son backups válidos
        if [ "$name" = "vscode_backups" ] || [ "$name" = "backups" ]; then
            continue
        fi
        
        # Ignorar backups temporales
        if [[ "$name" =~ ^temp_ ]]; then
            continue
        fi
        
        # Verificar si el directorio tiene contenido válido
        local has_content=false
        if [ -d "$dir/config" ] || [ -d "$dir/extensions" ] || [ -d "$dir/cache" ]; then
            has_content=true
        fi
        
        # Si no tiene contenido, verificar si tiene archivos
        if [ "$has_content" = false ]; then
            local file_count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
            local dir_count=$(find "$dir" -maxdepth 1 -type d ! -path "$dir" 2>/dev/null | wc -l)
            if [ "$file_count" -gt 0 ] || [ "$dir_count" -gt 0 ]; then
                has_content=true
            fi
        fi
        
        if [ "$has_content" = true ]; then
            # Verificar si el backup ya está en metadata
            local exists=$(jq -r ".backups[] | select(.name == \"$name\") | .name" "$BACKUP_METADATA_FILE" 2>/dev/null)
            if [ -z "$exists" ] || [ "$exists" = "null" ]; then
                echo "$name"
            fi
        fi
    done)
    
    if [ -n "$existing_backups" ]; then
        print_info "Recuperando backups existentes..."
        echo "$existing_backups" | while read -r name; do
            # Extraer fecha del nombre
            local date_part=$(echo "$name" | grep -oE '[0-9]{8}_[0-9]{6}' | head -1)
            if [ -z "$date_part" ]; then
                date_part=$(date +%Y%m%d_%H%M%S)
            fi
            
            # Agregar a metadata
            if add_backup_metadata "$name" "recovered" "Backup recuperado automáticamente" "$date_part"; then
                print_success "Backup recuperado: $name"
            else
                print_warning "No se pudo recuperar: $name"
            fi
        done
    fi
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

# Inicializar metadatos y recuperar backups existentes
init_metadata
recover_existing_backups

# Loop principal
while true; do
    show_menu
done
