# Working on Shiftland

Shiftland is a native workspace bar and settings app for macOS. This repository also contains its static website.

## Find the right code

| I want to change… | Start here |
| --- | --- |
| Workspace tiles, app icons, and their position on each display | [macos/Sources/WorkspaceBar/WorkspacePanel.swift](macos/Sources/WorkspaceBar/WorkspacePanel.swift) |
| App startup, status menu, display updates, or IPC reconnection | [macos/Sources/WorkspaceBar/Main.swift](macos/Sources/WorkspaceBar/Main.swift) |
| First-launch checks and OmniWM version selection | [SetupCompatibility.swift](macos/Sources/WorkspaceBar/SetupCompatibility.swift) and [WorkspaceSetupView.swift](macos/Sources/WorkspaceBar/WorkspaceSetupView.swift) |
| OmniWM event decoding or commands | [macos/Sources/WorkspaceBar/OmniWM.swift](macos/Sources/WorkspaceBar/OmniWM.swift) |
| The settings window or how edits are saved to OmniWM | [WorkspaceSettingsView.swift](macos/Sources/WorkspaceBar/WorkspaceSettingsView.swift) and [SettingsStore.swift](macos/Sources/WorkspaceBar/SettingsStore.swift) |
| The app's artwork or menu bar glyph | [macos/Resources/Brand/](macos/Resources/Brand/) and [ShiftlandStatusIcon.swift](macos/Sources/WorkspaceBar/ShiftlandStatusIcon.swift) |
| The public website, player, or build instructions | [web/index.html](web/index.html), [web/site.css](web/site.css), and [web/site.js](web/site.js) |
| The workspace demo video | [film/index.html](film/index.html) and [film/compositions/](film/compositions/) |
| How the website is deployed | [.github/workflows/pages.yml](.github/workflows/pages.yml) |
| Release builds, signing, notarization, and the files attached to a GitHub release | [.github/workflows/release.yml](.github/workflows/release.yml) and [macos/scripts/package-app.sh](macos/scripts/package-app.sh) |

Read [PRODUCT.md](PRODUCT.md) for the app's purpose and [DESIGN.md](DESIGN.md) for the identity and workspace bar. [README.md](README.md) is the contributor's starting point.

## macOS app

OmniWM owns tiling, workspace assignments, and the windows on each display. Shiftland subscribes through the installed `omniwmctl`, decodes workspace snapshots, and renders one bar per display. A workspace click sends a focus command back to OmniWM.

The Swift package is in `macos/`. From the repository root:

```sh
swift test --package-path macos -j 2 --filter WorkspaceBarTests
./scripts/build-app.sh
open -n "$PWD/.build/Shiftland.app" --args --preview --settings
```

`scripts/build-app.sh` calls the macOS build script and writes the bundle to `.build/Shiftland.app`. The `SHIFTLAND_*` variables documented at the top of that script switch it to a universal release build with a version and a Developer ID signature. `scripts/package-app.sh` turns the bundle into the DMG, zip, and checksums that a release publishes, and notarizes them when given an App Store Connect API key. Merging a new `CFBundleShortVersionString` into `main`, or pushing a `v*` tag, runs both in GitHub Actions and publishes the release. Preview runs alongside the installed bar with saving and workspace-zero shortcut registration disabled. Use the preview for visual work. Test settings changes on a temporary configuration file. `SettingsStore` owns the backup and stale-file checks around edits to `settings.toml`.

The installed OmniWM and its enabled IPC are needed for a live check. Run `".build/Shiftland.app/Contents/MacOS/Shiftland" --diagnose` to check the connection and display assignments. Open the setup window with `--preview --setup` to check its device details alongside the installed app.

## Website

`web/` is the site root. `index.html` contains the copy and player, `site.css` styles the page, and `site.js` handles starting the demo and copying build commands. Run the local server from the repository root.

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory web
```

Open `http://127.0.0.1:8000/`. Test video playback with pointer and keyboard, check the copy button, and inspect a mobile and an ultrawide viewport. Keep asset paths relative so the site works within the `/shiftland/` URL prefix. GitHub Pages serves the contents of `web/` through the Pages workflow.

## Demo film

`film/` is the editable HyperFrames project. Its bar states come from the native SwiftUI workspace buttons. The surrounding windows show a staged Git branch and task-list review. Use [film/README.md](film/README.md) to preview a change and export the MP4 and poster that the site serves.

## Before committing

Run the focused checks for the part you changed. Keep personal OmniWM settings, generated app builds, screenshots of real workspaces, and local workflow files outside the commit. Keep the web-ready demo and its poster in `web/assets/`.
