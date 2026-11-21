# Working on Shiftland

Shiftland is a native macOS menu bar and settings app powered by OmniWM. This repository also contains its static website.

## Find the right code

| I want to change… | Start here |
| --- | --- |
| Workspace tiles, app icons, and their position on each display | [macos/Sources/WorkspaceBar/WorkspacePanel.swift](macos/Sources/WorkspaceBar/WorkspacePanel.swift) |
| App startup, status menu, display updates, or IPC reconnection | [macos/Sources/WorkspaceBar/Main.swift](macos/Sources/WorkspaceBar/Main.swift) |
| OmniWM event decoding or commands | [macos/Sources/WorkspaceBar/OmniWM.swift](macos/Sources/WorkspaceBar/OmniWM.swift) |
| The settings window or how edits are saved to OmniWM | [WorkspaceSettingsView.swift](macos/Sources/WorkspaceBar/WorkspaceSettingsView.swift) and [SettingsStore.swift](macos/Sources/WorkspaceBar/SettingsStore.swift) |
| The app's artwork or menu bar glyph | [macos/Resources/Brand/](macos/Resources/Brand/) and [ShiftlandStatusIcon.swift](macos/Sources/WorkspaceBar/ShiftlandStatusIcon.swift) |
| The public website or interactive workspace illustration | [web/index.html](web/index.html), [web/site.css](web/site.css), [web/preview.css](web/preview.css), and [web/preview.js](web/preview.js) |
| How the website is deployed | [.github/workflows/pages.yml](.github/workflows/pages.yml) |

Read [PRODUCT.md](PRODUCT.md) for the app's purpose and [DESIGN.md](DESIGN.md) for the identity and workspace bar. [README.md](README.md) is the contributor's starting point.

## macOS app

OmniWM owns tiling, workspace assignments, and the windows on each display. Shiftland subscribes through the installed `omniwmctl`, decodes workspace snapshots, and renders one bar per display. A workspace click sends a focus command back to OmniWM.

The Swift package is in `macos/`. From the repository root:

```sh
swift test --package-path macos -j 2 --filter WorkspaceBarTests
./scripts/build-app.sh
open -n "$PWD/.build/Shiftland.app" --args --preview --settings
```

`scripts/build-app.sh` calls the macOS build script and writes the bundle to `.build/Shiftland.app`. Preview runs alongside the installed bar with saving and workspace-zero shortcut registration disabled. Use the preview for visual work. Test settings changes on a temporary configuration file. `SettingsStore` owns the backup and stale-file checks around edits to `settings.toml`.

The installed OmniWM and its enabled IPC are needed for a live check. Run `".build/Shiftland.app/Contents/MacOS/Shiftland" --diagnose` to check the connection and display assignments.

## Website

`web/` is the site root. `index.html` contains the copy and example window content. `site.css` styles the page, `preview.css` styles the illustration, `preview.js` switches workspaces, and `site.js` handles copying build commands. Serve it from the repository root:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory web
```

Open `http://127.0.0.1:8000/`. Test the workspace selector with pointer and keyboard, check the copy button, and inspect at least one narrow and one wide layout. Keep asset paths relative so the site works within the `/shiftland/` URL prefix. GitHub Pages serves the contents of `web/` through the Pages workflow.

## Before committing

Run the focused checks for the part you changed. Keep personal OmniWM settings, generated builds, screenshots of real workspaces, and local workflow files outside the commit. Use synthetic application names in the website preview so it can be published alongside the code.
