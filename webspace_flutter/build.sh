#!/usr/bin/env bash
# WebSpace Linux release build.
#
#   ./build.sh
#
# Produces:
#   dist/webspace/            the Flutter release bundle (binary "webspace")
#   dist/webspace.desktop     desktop entry with absolute Exec/Icon paths
#
# The libsecret-1 dev package is vendored under linux/deps/ because
# flutter_secure_storage's Linux plugin requires its headers at build time
# and they are not part of a base Flutter install.
set -euo pipefail
cd "$(dirname "$0")"

# --- libsecret build dependency -------------------------------------------
if pkg-config --exists libsecret-1 2>/dev/null; then
  echo ">> using system libsecret-1"
else
  DEPS="$PWD/linux/deps"
  EXTRACT="$DEPS/.libsecret"
  PC_DIR="$EXTRACT/usr/lib/x86_64-linux-gnu/pkgconfig"
  if [ ! -f "$PC_DIR/libsecret-1.pc" ]; then
    echo ">> extracting vendored libsecret-1-dev"
    mkdir -p "$EXTRACT"
    dpkg-deb -x "$DEPS"/libsecret-1-dev_*.deb "$EXTRACT"
    # The packaged .pc ships prefix=/usr — point it at the extraction dir.
    # Also drop Requires.private (libgcrypt): only needed for static linking
    # and not present on minimal build hosts.
    sed -i -e "s|^prefix=/usr|prefix=$EXTRACT/usr|" \
           -e "/^Requires.private:/d" "$PC_DIR/libsecret-1.pc"
    # The dev package ships libsecret-1.so as a relative symlink to the
    # runtime .so.0, which is not part of the deb — point it at the system
    # runtime library so the linker can resolve -lsecret-1.
    ln -sf /usr/lib/x86_64-linux-gnu/libsecret-1.so.0 \
      "$EXTRACT/usr/lib/x86_64-linux-gnu/libsecret-1.so"
  fi
  export PKG_CONFIG_PATH="$PC_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  echo ">> using vendored libsecret-1"
fi

# --- build -----------------------------------------------------------------
flutter build linux --release

BUNDLE="build/linux/x64/release/bundle"
DIST="dist/webspace"
rm -rf dist
mkdir -p "$DIST"
cp -a "$BUNDLE/." "$DIST/"
cp assets/icon.png "$DIST/webspace.png"

sed -e "s|@EXEC@|$PWD/$DIST/webspace|" \
    -e "s|@ICON@|$PWD/$DIST/webspace.png|" \
    packaging/webspace.desktop > dist/webspace.desktop

echo ""
echo "Bundle:        $DIST/webspace"
echo "Desktop entry: dist/webspace.desktop"
echo "To install:    cp dist/webspace.desktop ~/.local/share/applications/"
echo "               update-desktop-database ~/.local/share/applications/"
