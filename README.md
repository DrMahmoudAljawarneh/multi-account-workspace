# WebSpace - Multi-Account Isolated WebSpace

**WebSpace** is a modern, production-grade desktop application built with **Electron** that organizes and isolates multiple web services, accounts, and communication tools (WhatsApp, Teams, Overleaf, Facebook, Gmail, etc.) into distinct profiles with hardware-sandboxed cookie and session storage.

Designed for productivity on modern **Linux (Ubuntu, Asahi Linux, Wayland)** and **Windows 11**.

---

## 🚀 Key Features

### 🛡️ Profile & Session Isolation
- **Persistent Partitioning:** Separate profiles (e.g., *Personal*, *Work*) use dedicated cookie and cache jars (`persist:ProfileName`). You can stay logged into multiple Google, Microsoft, or Meta accounts simultaneously without conflicts.
- **True Favicons:** Auto-fetches crisp, high-resolution service icons using domain lookups to eliminate generic SSO/login favicons.

### ⚡ Performance & Linux Tuning
- **Wayland & Ozone Native:** Automatically selects the best display platform (`ozone-platform-hint=auto`) to avoid blurry XWayland scaling.
- **Smart Lazy Loading & RAM Hibernation:** Tabs are only initialized on first access. Tabs inactive for over 20 minutes automatically unload to free system memory.
- **Cache Caps & CPU Throttling:** Disk cache is capped at 256 MB to avoid unbounded directory growth; background timers throttle to minimize CPU drain.
- **Safe Sandboxing:** Runs cleanly without requiring root SUID permissions or disabling security protections.

### 🖥️ Modern UX & Controls
- **Command Palette (`Ctrl + K`):** Spotlight-style fuzzy search to switch between apps, toggle Split View, and trigger commands instantly via keyboard.
- **Interactive Split View:** View two workspaces side-by-side with a draggable divider to dynamically resize proportions.
- **Custom Frameless Titlebar:** Seamless integration with Linux-native minimize, maximize, and close controls, alongside a draggable window region.
- **Top Loading Pulse:** NProgress-style 2px gradient progress bar providing responsive loading feedback.
- **In-App Toast Banners:** Clean, unobtrusive status toasts replacing intrusive dialog popups.

### 🔒 Security & Privacy
- **Secure Architecture:** Complete context isolation (`contextIsolation: true`, `nodeIntegration: false`) with a typed `preload.js` bridge.
- **Hardware Permission Dialogs:** Prompts before granting camera, microphone, or location access to web views.
- **Smart External Link Router:** Links clicked inside web apps (e.g., Zoom links in emails) automatically open in your default system browser (Firefox/Chrome) rather than trapping you inside the app window.
- **Ultimate Botguard Bypass:** Natively spoofs Firefox 157.0 across network headers and the DOM (destroying Chromium client hints and `userAgentData`) to guarantee 100% successful Google Account sign-ins without "This browser is not secure" errors.

### ⚙️ Power-User Customization
- **In-App Settings UI:** Edit and reload your `config.json` directly from the toolbar (`⚙️ Settings`).
- **Per-App Custom CSS:** Inject user styles per service (e.g., custom dark mode or removing distracting UI sidebars).
- **Global Shortcuts:**
  - `Ctrl + 1` to `Ctrl + 9`: Quick switch to apps
  - `Ctrl + B`: Toggle sidebar collapse
  - `Ctrl + K`: Open Command Palette

---

## 🛠️ Getting Started (Development)

### Prerequisites
- Node.js (v18 or higher recommended)
- npm

### Installation & Local Run
```bash
# Navigate to the project directory
cd electron_prototype

# Install dependencies
npm install

# Start the application in development mode
npm start
```
*Or use the convenience script:*
```bash
./run_electron.sh
```

---

## 📦 Building Installers

### 1. Build for Linux (.deb & .AppImage)
Generates native Debian/Ubuntu packages and standalone AppImages:
```bash
npm run build
```
Outputs in `dist/`:
- `dist/WebSpace-1.0.4.AppImage`
- `dist/webspace_1.0.4_amd64.deb`

### 2. Build for Windows 11 (.exe)
Generates an NSIS setup executable:
```bash
npm run build:win
```
Outputs in `dist/`:
- `dist/WebSpace Setup 1.0.4.exe`

*(Note: Building Windows binaries locally from Linux requires Wine. Alternatively, use GitHub Actions below).*

---

## ☁️ Automated CI/CD via GitHub Actions

This repository includes two workflows:

- **`.github/workflows/build.yml`** — builds the Electron Linux and Windows binaries concurrently in the cloud:

1. Push your code to GitHub:
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin main
   ```
2. Navigate to your repository on GitHub and open the **Actions** tab.
3. Once the build completes, download your ready-to-run installers directly from the **Artifacts** or **Releases** section.

- **`.github/workflows/flutter.yml`** — runs the Flutter gate (`flutter analyze`, `flutter test`, `./build.sh`) and uploads the Linux `.deb` + desktop entry as artifacts. The same gate runs locally with:

```bash
./webspace_flutter/ci.sh
```

---

## 🐧 WebSpace Flutter (native Linux build)

`webspace_flutter/` is a native GTK/Flutter port of WebSpace with the same
feature set (profiles from the shared `config.json`, split view, command
palette, credential vault, hibernation, tray) plus native-only niceties.

### Prerequisites
- Flutter SDK (stable channel)
- `libsecret-1` runtime (already present on most desktops; the `-dev`
  headers are vendored in `webspace_flutter/linux/deps/` and extracted
  automatically by `build.sh` if the system lacks them)

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
- `dist/webspace_<ver>_amd64.deb` — self-contained Debian package
  (`/opt/webspace` + `/usr/bin/webspace` wrapper; install with
  `sudo dpkg -i`). Version override: `WEBSPACE_VERSION=x.y.z ./build.sh`.
  *(AppImage is not built — it requires downloading `appimagetool`.)*

### Flutter-only shortcuts & behaviors
- `Ctrl + 1…9`, `Ctrl+K`, `Ctrl+B`, `Ctrl+F`, `Ctrl+Shift+S`, `Ctrl+Shift+M`,
  `Ctrl +/−/0` — same as Electron; **Ctrl + wheel** also zooms the current app.
- **Split view panes have slim headers**: click a header to focus that pane —
  sidebar picks, `Ctrl+1…9`, find, toolbar nav and mute/zoom then target it.
  The main header hosts **swap panes**, the second header **close split**.
- **Window placement & zoom state persist** across restarts
  (`session.flutter.json` next to `config.json`, alongside Electron's
  `session.json` — the three schemas never touch each other or `settings.json`).
- **Camera / microphone requests prompt** before access (deny-by-default
  otherwise); JS `alert()/confirm()/prompt()` show real dialogs instead of
  being silently auto-confirmed.
- **Auto-fill is domain-gated**: credentials are only offered on the
  profile's own domain(s) (registrable-domain match). Submitting a real
  login form raises a *"Save password for …?"* snackbar; entries store an
  optional `domain` for matching and show it in the vault.
- `target=_blank` / `window.open` links load **in the same pane** (native
  plugin behavior — WebSpace has no popup windows). Downloads are handled by
  WebKitGTK directly (no in-app download UI yet).

---

## ⚙️ Configuration Format (`config.json`)

Your services and profiles are defined in `config.json`:

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

---

## 📄 License
MIT License. Free to use, modify, and distribute.
