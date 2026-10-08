# WebSpace

A centralized, sandboxed hub for managing various web applications and accounts cleanly on a single desktop (supporting Linux and Windows 11).

## Core Features
* **Profile and Session Isolation:** Organize web services (WhatsApp, Teams, Gmail) into distinct profiles (e.g., Personal, Work). Each profile uses dedicated cookie and session storage, enabling simultaneous logins from the same provider without conflict.
* **Performance and Resource Management:** Tuned for performance with lazy loading (tabs initialized when accessed) and RAM hibernation (inactive tabs unloaded after 20 minutes). Native Wayland support on Linux.
* **Modern UI/UX:** Spotlight-style command palette (Ctrl + K) for quick switching, an interactive side-by-side split view, and a custom frameless titlebar integrated with the OS.
* **Security and Privacy:** Strict context isolation, hardware permission prompts, and external links automatically open in the system default browser. Specific bypasses for seamless Google sign-ins without security warnings.
* **Customization:** Configurable via `config.json`, per-app custom CSS, and global keyboard shortcuts.

## Architecture

This app is built with Flutter.

* **UI Layer:** Implements the modern frameless window, command palette (`Ctrl + K`), and sidebar navigation.
* **State Management:** (To be determined - Provider/Riverpod/Bloc) for handling active sessions, tabs, and profiles.
* **Webview Integration:** Utilizes platform-specific webview implementations to handle session isolation and Wayland compatibility.
