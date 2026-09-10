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
API_BIN="$DIST/mous-api"
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
  --onefile \
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
test -x "$API_BIN"

echo "==> Assemble $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/migrations"
cp "$SWIFT_BIN" "$MACOS/Mous"
cp "$API_BIN" "$MACOS/mous-api"
chmod +x "$MACOS/Mous" "$MACOS/mous-api"
cp "$ROOT/macos/Mous/Sources/Mous/Info.plist" "$CONTENTS/Info.plist"
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
hdiutil create -volname Mous -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo
echo "Built:"
echo "  $APP"
echo "  $DMG"
echo "Open once with right-click → Open if Gatekeeper blocks it."
