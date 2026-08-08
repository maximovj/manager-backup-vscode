#!/bin/bash
# Script multiplataforma para Linux, macOS y Windows

echo "========================================"
echo "  Hola Mundo Multiplataforma"
echo "========================================"
echo ""

# Detectar sistema operativo
OS="$(uname -s)"
case "$OS" in
    Linux*)     echo "🐧 Sistema: Linux" ;;
    Darwin*)    echo "🍎 Sistema: macOS" ;;
    CYGWIN*|MINGW*|MSYS*) 
                echo "🪟 Sistema: Windows" ;;
    *)          echo "❓ Sistema: $OS" ;;
esac

echo "Usuario: $(whoami)"
echo "Fecha: $(date)"
echo "Bash versión: ${BASH_VERSION}"
echo ""
echo "¡Script ejecutado exitosamente! 🎉"