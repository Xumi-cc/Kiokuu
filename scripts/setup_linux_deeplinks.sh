#!/bin/bash

# Linux Deep Link Setup Script
# Run this after installing the app to enable musiccloud:// URL scheme

APP_NAME="music_cloud"
DESKTOP_FILE="$HOME/.local/share/applications/${APP_NAME}.desktop"
BINARY_PATH="$1"

if [ -z "$BINARY_PATH" ]; then
    echo "Usage: $0 /path/to/music_cloud"
    echo ""
    echo "Example: $0 /usr/local/bin/music_cloud"
    echo "         $0 ~/.local/bin/music_cloud"
    exit 1
fi

# Create applications directory if it doesn't exist
mkdir -p "$HOME/.local/share/applications"

# Create the .desktop file
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Music Cloud
Comment=Your personal music streaming app
Exec=$BINARY_PATH %u
Icon=music_cloud
Terminal=false
Type=Application
Categories=Audio;Music;Player;
Keywords=music;audio;streaming;playlist;
StartupNotify=true
MimeType=x-scheme-handler/musiccloud;
EOF

echo "✅ Created desktop file: $DESKTOP_FILE"

# Update desktop database
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Register the URL scheme
xdg-mime default "${APP_NAME}.desktop" x-scheme-handler/musiccloud

echo "✅ Registered musiccloud:// URL scheme"
echo ""
echo "Deep linking is now enabled! Test with:"
echo "  xdg-open 'musiccloud://share/test-token'"
