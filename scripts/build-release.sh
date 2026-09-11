#!/usr/bin/env bash
# Assemble dist/Mous.app (UI + bundled API) and dist/Mous-<version>.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(uv run python -c "import tomllib, pathlib; print(tomllib.loads(pathlib.Path('pyproject.toml').read_text())['project']['version'])")"
DIST="$ROOT/dist"
APP="$DIST/Mous.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SWIFT_BIN="$ROOT/macos/Mous/.build/release/Mous"
API_DIR="$DIST/mous-api"
DEVELOPER_DIR_DEFAULT="/Library/Developer/CommandLineTools"

if [[ -z "${DEVELOPER_DIR:-}" && -d "$DEVELOPER_DIR_DEFAULT" && ! -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="$DEVELOPER_DIR_DEFAULT"
fi

mkdir -p "$DIST"

echo "==> Swift release build"
swift build --package-path "$ROOT/macos/Mous" --configuration release --product Mous

echo "==> Frozen API (PyInstaller)"
uv sync --frozen --group release
uv run pyinstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name mous-api \
  --distpath "$DIST" \
  --workpath "$DIST/pyinstaller-work" \
  --specpath "$DIST/pyinstaller-work" \
  --collect-all oxyde \
  --collect-all oxyde_core \
  --collect-all uvicorn \
  --collect-all fastapi \
  --collect-all pydantic \
  --hidden-import mous.db.models \
  --hidden-import oxyde_config \
  --add-data "$ROOT/migrations:migrations" \
  --add-data "$ROOT/oxyde_config.py:." \
  "$ROOT/scripts/mous_api_entry.py"

test -x "$SWIFT_BIN"
test -x "$API_DIR/mous-api"
test -f "$ROOT/macos/Mous/Icon/AppIcon.icns"

echo "==> Assemble $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/migrations"
cp "$SWIFT_BIN" "$MACOS/Mous"
rm -rf "$MACOS/mous-api"
cp -R "$API_DIR" "$MACOS/mous-api"
chmod +x "$MACOS/Mous" "$MACOS/mous-api/mous-api"
cp "$ROOT/macos/Mous/Sources/Mous/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/macos/Mous/Icon/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/macos/Mous/Icon"/logo-variant.png "$RESOURCES/"
cp "$ROOT/macos/Mous/Icon"/logo-variant-*.png "$RESOURCES/"
cp "$ROOT/migrations/"*.py "$RESOURCES/migrations/"
cp "$ROOT/oxyde_config.py" "$RESOURCES/oxyde_config.py"

# Ad-hoc sign so Gatekeeper at least sees a signature on this Mac.
if command -v codesign >/dev/null; then
  echo "==> Ad-hoc codesign"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

DMG="$DIST/Mous-${VERSION}.dmg"
echo "==> $DMG"
rm -f "$DMG"
for vol in /Volumes/Mous /Volumes/Mous\ 1; do
  [ -d "$vol" ] && hdiutil detach "$vol" -force >/dev/null 2>&1 || true
done

uv run dmgbuild \
  -s "$ROOT/scripts/dmg_settings.py" \
  -D app="$APP" \
  -D background="$ROOT/macos/Mous/Icon/dmg-background.png" \
  -D icon="$ROOT/macos/Mous/Icon/AppIcon.icns" \
  "Mous" \
  "$DMG"

echo
echo "Built:"
echo "  $APP"
echo "  $DMG"
echo "Open the DMG and drag Mous onto Applications."
