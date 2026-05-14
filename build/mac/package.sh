#!/usr/bin/env bash
# AudioBookConverter – macOS packaging script
# Creates a self-contained .app bundle using jlink + jpackage.
#
# Prerequisites:
#   - Java 25 JDK in JAVA_HOME (must include jmods/)
#   - The project has been built: mvn package -DskipTests
#   - brew install ffmpeg mp4v2  (tools are expected at Homebrew paths at runtime)
#
# Usage:
#   JAVA_HOME=/path/to/jdk25 ./build/mac/package.sh [version]
#   If [version] is omitted, it is read from version.txt.

set -euo pipefail

# ── Version ──────────────────────────────────────────────────────────────────
APP_VERSION="${1:-$(cat version.txt)}"
# jpackage requires a numeric version (no -SNAPSHOT suffix)
JPACKAGE_VERSION="${APP_VERSION%-SNAPSHOT}"
echo "Building AudioBookConverter $APP_VERSION (app version: $JPACKAGE_VERSION) for macOS"

# ── Java home ────────────────────────────────────────────────────────────────
if [ -z "${JAVA_HOME:-}" ]; then
  echo "ERROR: JAVA_HOME is not set. Export it to a Java 25 JDK, e.g.:"
  echo "  export JAVA_HOME=\$(/usr/libexec/java_home -v 25)"
  exit 1
fi
echo "Using JAVA_HOME: $JAVA_HOME"

# ── Detect architecture and select the right JavaFX jmods ZIP ────────────────
ARCH="$(uname -m)"
JAVAFX_JMODS_DIR="target/fx-jmods"

if [ "$ARCH" = "arm64" ]; then
  JAVAFX_ZIP=$(ls javafx/jmods/openjfx-*_osx-aarch64_bin-jmods.zip 2>/dev/null | head -1)
else
  JAVAFX_ZIP=$(ls javafx/jmods/openjfx-*_osx-x64_bin-jmods.zip 2>/dev/null | head -1)
fi

if [ -z "${JAVAFX_ZIP:-}" ]; then
  echo "ERROR: No matching JavaFX jmods ZIP found in javafx/jmods/ for arch $ARCH"
  exit 1
fi
echo "Using JavaFX jmods: $JAVAFX_ZIP"

# Extract the jmods ZIP into a temp directory (only if stale)
if [ ! -d "$JAVAFX_JMODS_DIR" ] || [ "$JAVAFX_ZIP" -nt "$JAVAFX_JMODS_DIR" ]; then
  rm -rf "$JAVAFX_JMODS_DIR"
  mkdir -p "$JAVAFX_JMODS_DIR"
  unzip -q "$JAVAFX_ZIP" -d "$JAVAFX_JMODS_DIR"
  # The zip extracts into a versioned subdirectory; find the jmods folder
  JAVAFX_JMODS_DIR="$(find "$JAVAFX_JMODS_DIR" -type d -name jmods | head -1)"
fi
echo "JavaFX jmods directory: $JAVAFX_JMODS_DIR"

# ── Input package directory (produced by mvn package) ────────────────────────
INPUT_DIR="target/package/audiobookconverter-${APP_VERSION}-mac-installer/audiobookconverter-${APP_VERSION}/app"
if [ ! -d "$INPUT_DIR" ]; then
  echo "ERROR: Maven package output not found at $INPUT_DIR"
  echo "Run: mvn package -DskipTests"
  exit 1
fi

# ── jlink – build a minimal JRE ──────────────────────────────────────────────
echo "Creating custom JRE with jlink…"
rm -rf target/fx-jre
"$JAVA_HOME/bin/jlink" \
  --module-path "$JAVA_HOME/jmods:$JAVAFX_JMODS_DIR" \
  --add-modules java.base,java.sql,java.management,javafx.controls,javafx.fxml,javafx.media,javafx.base,javafx.swing,javafx.graphics \
  --strip-native-commands --strip-debug --no-man-pages --no-header-files \
  --exclude-files='**.md' \
  --output target/fx-jre

# ── jpackage – build the .app bundle ─────────────────────────────────────────
echo "Creating .app bundle with jpackage…"
rm -rf target/release
mkdir -p target/release

"$JAVA_HOME/bin/jpackage" \
  --app-version "$JPACKAGE_VERSION" \
  --icon build/mac/AudiobookConverter.icns \
  --type app-image \
  --input "$INPUT_DIR" \
  --main-jar "lib/audiobookconverter-${APP_VERSION}.jar" \
  --runtime-image target/fx-jre \
  --java-options "--enable-preview --add-exports java.desktop/com.apple.eio=ALL-UNNAMED" \
  --dest target/release \
  --vendor "Recoupler Limited" \
  --app-version "$JPACKAGE_VERSION" \
  --mac-package-identifier com.recoupler.abc \
  --mac-package-name AudioBookConverter

# Optional code signing — only attempted when a signing identity is available.
SIGNING_IDENTITY="${MAC_SIGNING_IDENTITY:-}"
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "Signing with identity: $SIGNING_IDENTITY"
  "$JAVA_HOME/bin/jpackage" \
    --app-version "$JPACKAGE_VERSION" \
    --icon build/mac/AudiobookConverter.icns \
    --type app-image \
    --input "$INPUT_DIR" \
    --main-jar "lib/audiobookconverter-${APP_VERSION}.jar" \
    --runtime-image target/fx-jre \
    --java-options "--enable-preview --add-exports java.desktop/com.apple.eio=ALL-UNNAMED" \
    --dest target/release \
    --vendor "Recoupler Limited" \
    --app-version "$JPACKAGE_VERSION" \
    --mac-entitlements build/mac/entitlements.plist \
    --mac-package-identifier com.recoupler.abc \
    --mac-package-name AudioBookConverter \
    --mac-signing-key-user-name "$SIGNING_IDENTITY" \
    --mac-sign
else
  echo "MAC_SIGNING_IDENTITY not set — skipping code signing (unsigned build)."
fi

echo ""
echo "Done! App bundle: target/release/AudioBookConverter.app"
