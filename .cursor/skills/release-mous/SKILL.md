---
name: release-mous
description: >-
  Builds a drag-and-drop Mous.app (popup + bundled API) and publishes a GitHub
  Release with a .dmg. Use when the user asks to release mous, ship a dmg,
  tag a version, or package the macOS app.
disable-model-invocation: true
---

# Release mous

One downloadable file: `dist/Mous-<version>.dmg` containing `Mous.app`.
The app starts and stops its own API. Do not tell users to run Docker.

Never commit `dist/`. Never force-push tags. Never delete a GitHub release.

## Checklist

Copy and tick:

```
- [ ] Working tree clean (or only the version bump)
- [ ] Version bumped in pyproject.toml and Info.plist
- [ ] Swift checks + API smoke
- [ ] ./scripts/build-release.sh
- [ ] Smoke the .app
- [ ] Commit version bump only
- [ ] Tag vX.Y.Z and push
- [ ] gh release with the .dmg
```

## 1. Version

Read `pyproject.toml` `[project].version` and
`macos/Mous/Sources/Mous/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`).

Bump all three together:

- `pyproject.toml` → `X.Y.Z`
- `CFBundleShortVersionString` → `X.Y.Z`
- `CFBundleVersion` → integer + 1

Default bump is patch (`0.1.0` → `0.1.1`) unless the user asked otherwise.

## 2. Checks

```sh
uv run python -c "from mous.api.app import create_app; create_app()"
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
  swift run --package-path macos/Mous MousCoreCheck
```

Stop if either fails.

## 3. Build

```sh
./scripts/build-release.sh
```

Expect:

- `dist/Mous.app` — UI at `Contents/MacOS/Mous`, helper at `Contents/MacOS/mous-api`
- `dist/Mous-<version>.dmg`

The script ad-hoc signs. Developer ID + notarize only if the user has an
Apple signing identity and asked for it.

## 4. Smoke the app

Quit any running `Mous`, then:

```sh
open dist/Mous.app
sleep 5
curl -sS http://127.0.0.1:8000/health   # {"status":"ok"}
```

Confirm `~/Library/Application Support/mous/data.db` exists. Quit Mous
(`osascript -e 'tell application "Mous" to quit'`).

## 5. Publish

Commit **only** the version files (`pyproject.toml`, `uv.lock` if it changed,
`Info.plist`). Message: `Release vX.Y.Z`.

```sh
git tag vX.Y.Z
git push origin HEAD
git push origin vX.Y.Z
gh release create "vX.Y.Z" --title "mous X.Y.Z" \
  --notes "Drag Mous.app to Applications. Right-click → Open the first time if Gatekeeper warns." \
  "dist/Mous-X.Y.Z.dmg"
```

Return the release URL. Do not push unless this skill is running a release
the user asked for.

## Layout (do not invent a new one)

```
Mous.app/
  Contents/MacOS/Mous          # Swift popup
  Contents/MacOS/mous-api      # frozen FastAPI
  Contents/Resources/migrations/
  Contents/Resources/oxyde_config.py
  Contents/Info.plist
```

User data: `~/Library/Application Support/mous/data.db`
Helper logs: `~/Library/Application Support/mous/logs/`

Dev (`uv run mous dev`) does **not** spawn `mous-api`; it talks to whatever
is already on `127.0.0.1:8000`.
