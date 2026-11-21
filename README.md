# Shiftland

<img src="macos/Resources/Brand/AppIcon.png" width="96" height="96" alt="Shiftland's leaping hare">

Shiftland is a native workspace bar for macOS. See which apps are open in each space, switch with a click or shortcut, and organize your work across displays.

[Project website](https://ross-cripto.github.io/shiftland/) · [Download](https://github.com/Ross-cripto/shiftland/releases/latest) · [Report an issue](https://github.com/Ross-cripto/shiftland/issues/new)

## Download

Download `Shiftland.dmg` from the [latest release](https://github.com/Ross-cripto/shiftland/releases/latest), open it, and drag Shiftland to Applications. Shiftland runs on macOS 15 or later on Apple silicon and Intel Macs. Install [OmniWM](https://github.com/OmniNull/OmniWM) and enable IPC in its menu before you open Shiftland.

If the release notes say the build isn't notarized, macOS blocks Shiftland the first time you open it. Open it once, then go to System Settings → Privacy & Security and click **Open Anyway**.

## Find the code

| Path | What lives here |
| --- | --- |
| [macos/](macos/) | Swift package, native app, artwork, and tests |
| [web/](web/) | Public website source and assets. Start at [web/index.html](web/index.html) |
| [film/](film/) | HyperFrames source for the website's workspace demo |
| [scripts/](scripts/) | Root build and packaging entry points |
| [AGENTS.md](AGENTS.md) | Code map, architecture, and development commands |

## Build from source

You need macOS 15 or later and Xcode's command-line tools to build the Swift app. Install [OmniWM](https://github.com/OmniNull/OmniWM) in `/Applications` or `~/Applications` and enable IPC in its menu to connect Shiftland. The verified pairing is macOS 15.5 with OmniWM 0.5.1.

```sh
git clone https://github.com/Ross-cripto/shiftland.git
cd shiftland
./scripts/build-app.sh
open -n "$PWD/.build/Shiftland.app" --args --preview --settings
```

Preview mode shows the Shiftland bar below your current bar and lets you switch spaces. In that mode, saving and registering the two workspace-zero shortcuts are disabled. To use the normal bar, quit the preview, stop your previous bar and any helper that registers `⌥0` or `⌥⇧0`, then open `.build/Shiftland.app`.

Open settings from Shiftland's menu or by right-clicking a workspace. When you save, Shiftland backs up OmniWM's `settings.toml` in `workspace-bar-backups/` and checks whether the file changed while the settings were open.

## Contributing

Use [GitHub Issues](https://github.com/Ross-cripto/shiftland/issues) for bugs and ideas. For a bug, include your macOS and OmniWM versions, display setup, and steps to reproduce it. Remove any window titles or file paths you want to keep private.

```sh
swift test --package-path macos -j 2 --filter WorkspaceBarTests
./scripts/build-app.sh
".build/Shiftland.app/Contents/MacOS/Shiftland" --diagnose
```

To work on the website, serve `web/` with `python3 -m http.server 8000 --bind 127.0.0.1 --directory web` and open `http://127.0.0.1:8000/`. The site is plain HTML, CSS, and JavaScript.

## Publish a release

The [macOS app workflow](.github/workflows/release.yml) tests and packages Shiftland for every pull request that changes the app and every push to `main`. Download that build from the workflow run's **Artifacts**. To publish a release, push a version tag:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow writes the tag's version into the app, builds one universal binary for Apple silicon and Intel, and publishes `Shiftland.dmg`, `Shiftland.zip`, and `SHA256SUMS.txt` in a GitHub release with generated notes and a build provenance attestation. A tag with a suffix, such as `v0.2.0-beta.1`, becomes a prerelease and doesn't replace the latest release.

To build the same files locally:

```sh
SHIFTLAND_CONFIGURATION=release SHIFTLAND_UNIVERSAL=1 ./scripts/build-app.sh
./scripts/package-app.sh
```

They're written to `.build/dist/`.

### Sign and notarize releases

Without Apple credentials, releases are signed ad hoc, and macOS asks people to approve Shiftland in System Settings the first time they open it. To sign releases with Developer ID and have Apple notarize them, join the [Apple Developer Program](https://developer.apple.com/programs/) and add these secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Your Developer ID Application certificate and its private key. Create the certificate in Xcode under **Settings → Accounts → Manage Certificates**, export it from Keychain Access as a `.p12` file, and copy it with `base64 -i Certificates.p12 \| pbcopy`. |
| `APPLE_CERTIFICATE_PASSWORD` | The password you chose when you exported the `.p12` file. |
| `APPLE_NOTARY_KEY` | The contents of an App Store Connect API key file, `AuthKey_<ID>.p8`. Create a team key with Developer access in App Store Connect under **Users and Access → Integrations**. |
| `APPLE_NOTARY_KEY_ID` | The ID of that key. |
| `APPLE_NOTARY_ISSUER_ID` | The issuer ID shown above the list of keys. |

When all five secrets are set, tagged releases are signed with the hardened runtime, notarized, and stapled, so they open without a warning. The workflow stops if only some of them are set.

## License

Shiftland's source is available under the [MIT License](LICENSE). Shiftland communicates with a separately installed [OmniWM](https://github.com/OmniNull/OmniWM) through its `omniwmctl` command. OmniWM is distributed under its [own GPL-2.0 license](https://github.com/OmniNull/OmniWM/blob/main/LICENSE). The website uses Bricolage Grotesque under the [SIL Open Font License](web/assets/bricolage-OFL.txt).
