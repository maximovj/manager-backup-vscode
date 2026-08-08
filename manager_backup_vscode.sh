#!/usr/bin/env bash
# Script de configuración multiplataforma para VSCode

# ============================================
# DETECTAR SISTEMA OPERATIVO
# ============================================
OS="$(uname -s)"
case "$OS" in
    Linux*)     PLATFORM="linux" ;;
    Darwin*)    PLATFORM="macos" ;;
    CYGWIN*|MINGW*|MSYS*|Windows*) 
                PLATFORM="windows" ;;
    *)          PLATFORM="unknown" ;;
esac

# ============================================
# CONFIGURACIÓN MULTIPLATAFORMA
# ============================================

# Directorio base de configuración de VSCode
case "$PLATFORM" in
    linux|macos)
        VSCODE_CONFIG_DIR="$HOME/.config/Code"
        VSCODE_USER_DIR="$HOME/.config/Code/User"
        VSCODE_EXTENSIONS_DIR="$HOME/.vscode/extensions"
        VSCODE_CACHE_DIR="$HOME/.cache/vscode-cpptools"
        ;;
    windows)
        # En Windows con WSL/Git Bash
        VSCODE_CONFIG_DIR="$APPDATA/Code"  # o "$USERPROFILE/AppData/Roaming/Code"
        VSCODE_USER_DIR="$APPDATA/Code/User"
        VSCODE_EXTENSIONS_DIR="$USERPROFILE/.vscode/extensions"
        VSCODE_CACHE_DIR="$USERPROFILE/AppData/Local/Temp/vscode-cpptools"
        ;;
    *)
        echo "❌ Sistema no soportado: $OS"
        exit 1
        ;;
esac

# ============================================
# DIRECTORIOS DE BACKUP (multiplataforma)
# ============================================
BACKUP_BASE_DIR="$HOME/vscode_backups"
BACKUP_METADATA_FILE="$BACKUP_BASE_DIR/metadata.json"
EXPORT_DEFAULT_DIR="$HOME"
MAX_BACKUPS=20

# ============================================
# FUNCIONES DE UTILIDAD
# ============================================

# Función para crear directorios de forma segura
create_dirs() {
    for dir in "$@"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" 2>/dev/null || {
                echo "⚠️ No se pudo crear: $dir"
                return 1
            }
        fi
    done
}

# Función para mostrar configuración actual
show_config() {
    echo "============================================"
    echo "  📋 Configuración VSCode Multiplataforma"
    echo "============================================"
    echo "🖥️  Sistema: $PLATFORM ($OS)"
    echo "📁 Config: $VSCODE_CONFIG_DIR"
    echo "👤 Usuario: $VSCODE_USER_DIR"
    echo "🧩 Extensiones: $VSCODE_EXTENSIONS_DIR"
    echo "💾 Caché: $VSCODE_CACHE_DIR"
    echo "💿 Backups: $BACKUP_BASE_DIR"
    echo "📊 Máx backups: $MAX_BACKUPS"
    echo "============================================"
}

# ============================================
# CREAR DIRECTORIOS NECESARIOS
# ============================================
echo "📁 Creando directorios necesarios..."
create_dirs "$BACKUP_BASE_DIR" "$VSCODE_CACHE_DIR"

# ============================================
# MOSTRAR CONFIGURACIÓN
# ============================================
show_config

# ============================================
# EJEMPLO DE USO
# ============================================
echo ""
echo "✅ Configuración lista para usar"
echo "💡 Los backups se guardarán en: $BACKUP_BASE_DIR"