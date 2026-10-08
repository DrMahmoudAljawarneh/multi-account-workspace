# WebSpace - Multi-Account Isolated WebSpace

**WebSpace** is a native Linux desktop application built with **Flutter/GTK** that organizes and isolates multiple web services, accounts, and communication tools (WhatsApp, Teams, Overleaf, Facebook, Gmail, etc.) into distinct profiles, each with its own cookie and session storage.

## Key Features

### Profile & Session Isolation
- **Persistent per-app storage:** each profile keeps its own cookies and cache. Stay logged into multiple Google, Microsoft, or Meta accounts simultaneously without conflicts.
- **True Favicons:** auto-fetches crisp, high-resolution service icons using domain lookups to eliminate generic SSO/login favicons.

### Performance
- **Lazy loading & RAM hibernation:** webviews initialize on first access; apps inactive beyond the configured timeout unload to free memory.
- **Fast native shell:** Flutter/GTK UI with WebKitGTK webviews.

### Modern UX & Controls
- **Command Palette (`Ctrl + K`):** fuzzy search to switch between apps, toggle split view, and trigger commands instantly via keyboard.
- **Split View with pane headers:** two workspaces side-by-side with a draggable divider. Click a header to focus that pane — sidebar picks, `Ctrl+1…9`, find, toolbar nav and mute/zoom then target it. The main header hosts **swap panes**, the second header **close split**.
- **Custom frameless titlebar** with native minimize, maximize, and close controls.
- **Find in page (`Ctrl+F`)**, per-app zoom (`Ctrl +/−/0`, `Ctrl + wheel`), per-app mute (`Ctrl+Shift+M`), sidebar toggle (`Ctrl+B`).
- **Window placement & zoom state persist** across restarts (`session.flutter.json` next to `config.json`).

### Security & Privacy
- **Hardware permission dialogs:** camera, microphone, and location requests prompt before access (deny-by-default otherwise). JS `alert()/confirm()/prompt()` show real dialogs instead of being silently auto-confirmed.
- **Domain-gated auto-fill:** vault credentials are only offered on the profile's own domain(s). Submitting a real login form raises a *"Save password for …?"* prompt; entries store an optional domain for matching.
- **Keyring-backed credential vault:** passwords live in the OS keyring (libsecret), never in plaintext files.
- **External links** open in the default system browser rather than trapping you inside the app.

### Power-User Customization
- **In-app Settings UI:** edit profiles, theme, and behavior from the toolbar (`Settings`), with a discard-guard for unsaved edits.
- **Per-app custom CSS:** inject user styles per service (e.g., custom dark mode).

## Getting Started (Development)

### Prerequisites
- Flutter SDK (stable channel)
- `libsecret-1` runtime (already present on most desktops; the `-dev` headers are vendored in `webspace_flutter/linux/deps/` and extracted automatically by `build.sh` if the system lacks them)

### Run / build
```bash
cd webspace_flutter

# Development run
flutter run -d linux

# Full release gate (analyze + test + package)
./ci.sh

# Or just the release build + packaging
./build.sh
```

`build.sh` produces:
- `dist/webspace/` — release bundle (binary named `webspace`)
- `dist/webspace.desktop` — desktop entry with absolute paths (local install)
- `dist/webspace_<ver>_amd64.deb` — self-contained Debian package (`/opt/webspace` + `/usr/bin/webspace` wrapper; install with `sudo dpkg -i`). Version override: `WEBSPACE_VERSION=x.y.z ./build.sh`. *(AppImage is not built — it requires downloading `appimagetool`.)*

### Notes & behaviors
- `Ctrl + 1…9`, `Ctrl+K`, `Ctrl+B`, `Ctrl+F`, `Ctrl+Shift+S`, `Ctrl+Shift+M`, `Ctrl +/−/0` — global shortcuts; `Ctrl + wheel` also zooms the current app.
- `target=_blank` / `window.open` links load **in the same pane** (native plugin behavior — WebSpace has no popup windows). Downloads are handled by WebKitGTK directly (no in-app download UI yet).

## Automated CI/CD via GitHub Actions

`.github/workflows/flutter.yml` runs the Flutter gate (`flutter analyze`, `flutter test`, `./build.sh`) and uploads the Linux `.deb` + desktop entry as artifacts. The same gate runs locally with:

```bash
cd webspace_flutter && ./ci.sh
```

## Configuration Format (`config.json`)

Your services and profiles are defined in `config.json` (shared schema; `settings.json` holds UI settings, `session.flutter.json` holds per-session state next to it):

```json
{
  "Personal": [
    {
      "name": "WhatsApp",
      "url": "https://web.whatsapp.com"
    },
    {
      "name": "Overleaf",
      "url": "https://www.overleaf.com/project"
    }
  ],
  "Work": [
    {
      "name": "Teams",
      "url": "https://teams.microsoft.com",
      "customCSS": "/* Optional custom styling */"
    }
  ]
}
```

## License
MIT License. Free to use, modify, and distribute.
