#!/bin/bash
set -e

FLUTTER_VERSION="stable"
FLUTTER_HOME="$HOME/flutter"

echo "Checking Flutter CLI installation..."

# Check if Flutter is already installed and in PATH
if command -v flutter &> /dev/null; then
    echo "Flutter CLI is already installed:"
    flutter --version
    exit 0
fi

# Check if Flutter exists in home directory but not in PATH
if [ -d "$FLUTTER_HOME" ] && [ -f "$FLUTTER_HOME/bin/flutter" ]; then
    echo "Flutter found at $FLUTTER_HOME, adding to PATH..."
    export PATH="$PATH:$FLUTTER_HOME/bin"

    # Persist to CLAUDE_ENV_FILE for subsequent commands
    if [ -n "$CLAUDE_ENV_FILE" ]; then
        echo "export FLUTTER_HOME=$FLUTTER_HOME" >> "$CLAUDE_ENV_FILE"
        echo "export PATH=\$PATH:\$FLUTTER_HOME/bin" >> "$CLAUDE_ENV_FILE"
    fi

    flutter --version
    exit 0
fi

echo "Installing Flutter CLI ($FLUTTER_VERSION)..."

# Clone Flutter repository
git clone https://github.com/flutter/flutter.git -b $FLUTTER_VERSION --depth 1 "$FLUTTER_HOME"

# Add Flutter to PATH
export PATH="$PATH:$FLUTTER_HOME/bin"

# Persist environment variables for subsequent commands in this session
if [ -n "$CLAUDE_ENV_FILE" ]; then
    echo "export FLUTTER_HOME=$FLUTTER_HOME" >> "$CLAUDE_ENV_FILE"
    echo "export PATH=\$PATH:\$FLUTTER_HOME/bin" >> "$CLAUDE_ENV_FILE"
fi

# Skip precache/doctor - they download 300MB+ of platform tools
# Flutter will download what it needs lazily when you run build/test
echo "Flutter CLI installation complete!"
flutter --version

echo ""
echo "Note: Run 'flutter pub get' in your project to fetch dependencies."
