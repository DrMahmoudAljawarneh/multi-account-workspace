#!/bin/bash
set -e

echo "Building Flutter app for Linux (Release)..."
flutter build linux --release

APP_NAME="webspace-flutter"
APP_VERSION="1.0.0"
ARCHITECTURE="amd64"
DEB_DIR="build/debian/$APP_NAME"

echo "Cleaning up previous builds..."
rm -rf "$DEB_DIR"
mkdir -p build/debian

echo "Creating Debian package structure..."
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/opt/$APP_NAME"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_DIR/usr/bin"

echo "Copying build files..."
cp -r build/linux/x64/release/bundle/* "$DEB_DIR/opt/$APP_NAME/"

echo "Copying icon..."
cp assets/icon.png "$DEB_DIR/usr/share/icons/hicolor/256x256/apps/com.example.webspace_flutter.png"

echo "Creating desktop entry..."
cat <<EOF > "$DEB_DIR/usr/share/applications/com.example.webspace_flutter.desktop"
[Desktop Entry]
Version=1.0
Name=WebSpace
GenericName=WebSpace Browser
Comment=WebSpace Workspace Application
Exec=/opt/$APP_NAME/webspace_flutter
Icon=com.example.webspace_flutter
Terminal=false
Type=Application
Categories=Utility;
EOF

echo "Creating symlink for bin..."
ln -s /opt/$APP_NAME/webspace_flutter "$DEB_DIR/usr/bin/webspace-flutter"

echo "Creating DEBIAN/control file..."
cat <<EOF > "$DEB_DIR/DEBIAN/control"
Package: $APP_NAME
Version: $APP_VERSION
Section: utils
Priority: optional
Architecture: $ARCHITECTURE
Depends: libnotify4, libappindicator3-1
Maintainer: WebSpace Developer <dev@example.com>
Description: WebSpace Application
 A Flutter-based WebSpace workspace app with system tray and notifications.
EOF

echo "Building .deb package..."
dpkg-deb --build "$DEB_DIR"

echo "--------------------------------------------------------"
echo "✅ Package successfully built!"
echo "📦 Location: build/debian/${APP_NAME}.deb"
echo "🚀 To install, run:"
echo "sudo dpkg -i build/debian/${APP_NAME}.deb"
echo "--------------------------------------------------------"
