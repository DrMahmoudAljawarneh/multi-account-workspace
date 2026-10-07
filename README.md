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

This repository includes a pre-configured GitHub Actions workflow (`.github/workflows/build.yml`) that builds Linux and Windows binaries concurrently in the cloud:

1. Push your code to GitHub:
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin main
   ```
2. Navigate to your repository on GitHub and open the **Actions** tab.
3. Once the build completes, download your ready-to-run installers directly from the **Artifacts** or **Releases** section.

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
