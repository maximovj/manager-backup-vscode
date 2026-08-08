#!/usr/bin/env bash

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