const { app, BrowserWindow, ipcMain, session, dialog, shell, Tray, Menu, nativeImage, Notification, safeStorage, clipboard } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Linux Performance & Wayland Optimizations
app.commandLine.appendSwitch('enable-features', 'UseOzonePlatform,WaylandWindowDecorations');
app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
app.commandLine.appendSwitch('disk-cache-size', '268435456'); // Cap disk cache to 256MB
app.commandLine.appendSwitch('disable-gpu'); // Safe fallback for Asahi/mesa software stacks
// Hide automation fingerprint that Google's sign-in risk engine checks
app.commandLine.appendSwitch('disable-blink-features', 'AutomationControlled');
// Disable Client Hints so Google JS cannot read the real "Electron" brand via navigator.userAgentData
// Disable WebAuthentication completely so Microsoft's iframes cannot access FIDO2
app.commandLine.appendSwitch('disable-features', 'UserAgentClientHint,WebAuthentication');

// --- Google Sign-In & Bot-Detection Bypass ------------------------------------
const FIREFOX_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0';
const LINUX_CHROME_UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

app.userAgentFallback = LINUX_CHROME_UA;

function hardenSession(ses) {
    ses.setUserAgent(FIREFOX_UA);
    ses.webRequest.onBeforeSendHeaders((details, callback) => {
        const headers = details.requestHeaders;
        const url = details.url;
        
        // If it's a login page, we masquerade as an iPad.
        // Mobile devices do not use USB Security Keys (WebAuthn) in the same way,
        // so Microsoft gracefully falls back to sending an Authenticator Push Notification
        // or asking for a Password, completely eliminating the FIDO2 hang in Electron!
        if (url.includes('login.microsoft') || url.includes('login.live.com')) {
            headers['User-Agent'] = 'Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';
        } else {
            headers['User-Agent'] = FIREFOX_UA;
        }

        // Unconditionally strip out all Client Hints so no provider detects Electron
        for (const key of Object.keys(headers)) {
            if (key.toLowerCase().startsWith('sec-ch-ua')) delete headers[key];
        }
        
        callback({ requestHeaders: headers });
    });
}
app.on('session-created', hardenSession);
// -----------------------------------------------------------------------------

let mainWindow;
let tray;

// --- Global Shortcuts -------------------------------------------------------
// Key events inside <webview> guests never reach the renderer, so chrome
// shortcuts (Ctrl+K / Ctrl+B / Ctrl+1-9) are intercepted here in the main
// process and forwarded to the renderer over IPC.
let lastChord = { cmd: null, at: 0 };

function handleGlobalShortcut(event, input) {
    if (input.type !== 'keyDown') return;
    if (!input.control && !input.meta) return;

    const key = input.key.toLowerCase();
    let cmd = null;

    if (key === 'k') cmd = 'palette';
    else if (key === 'b') cmd = 'toggle-sidebar';
    else if (key === 'f') cmd = 'find';
    else if (key === 's' && input.shift) cmd = 'toggle-split';
    else if (key >= '1' && key <= '9') cmd = 'app:' + key;

    if (cmd) {
        event.preventDefault(); // Stop the guest page from also receiving the chord

        // When a webview guest has focus, BOTH the host and the guest emit
        // before-input-event for the same physical press — dedupe so each
        // chord is forwarded exactly once.
        const now = Date.now();
        if (cmd === lastChord.cmd && (now - lastChord.at) < 60) return;
        lastChord = { cmd, at: now };

        if (mainWindow && !mainWindow.isDestroyed()) {
            mainWindow.webContents.send('global-shortcut', cmd);
        }
    }
}
// ---------------------------------------------------------------------------

app.whenReady().then(() => {
    hardenSession(session.defaultSession);
    
    mainWindow = new BrowserWindow({
        width: 1240,
        height: 820,
        minWidth: 800,
        minHeight: 600,
        frame: false, // Linux Custom Titlebar
        icon: path.join(__dirname, 'build/icon.png'),
        backgroundColor: '#121212',
        webPreferences: {
            webviewTag: true,
            nodeIntegration: false,
            contextIsolation: true,
            preload: path.join(__dirname, 'preload.js'),
            backgroundThrottling: true // Linux battery & CPU save
        }
    });

    mainWindow.loadFile('index.html');

    // Chrome shortcuts must work even when a webview guest has keyboard focus
    mainWindow.webContents.on('before-input-event', handleGlobalShortcut);

    // System Tray Integration
    try {
        const trayIcon = nativeImage.createFromPath(path.join(__dirname, 'build/icon.png')).resize({ width: 24, height: 24 });
        tray = new Tray(trayIcon);
        const contextMenu = Menu.buildFromTemplate([
            { label: 'Show WebSpace', click: () => { mainWindow.show(); mainWindow.focus(); } },
            { label: 'Toggle Fullscreen', click: () => mainWindow.setFullScreen(!mainWindow.isFullScreen()) },
            { type: 'separator' },
            { label: 'Quit', click: () => app.quit() }
        ]);
        tray.setToolTip('WebSpace');
        tray.setContextMenu(contextMenu);
    } catch (e) {
        console.error("Tray error:", e);
    }
});

// Linux Window Control IPC Handlers
ipcMain.on('window-minimize', () => mainWindow && mainWindow.minimize());
ipcMain.on('window-maximize', () => {
    if (!mainWindow) return;
    if (mainWindow.isMaximized()) {
        mainWindow.unmaximize();
    } else {
        mainWindow.maximize();
    }
});
ipcMain.on('window-close', () => mainWindow && mainWindow.close());

// Config lookup — read and write MUST resolve to the same file, otherwise
// settings saved at runtime are silently written to a location never read again.
function resolveConfigPath() {
    const candidates = [
        path.join(__dirname, 'config.json'),                                   // dev / repo checkout
        path.join(os.homedir(), 'newapp', 'config.json'),                      // legacy location
        path.join(os.homedir(), '.my_webapp_data', 'config.json'),             // legacy location
        path.join(app.getPath('userData'), 'config.json')                      // packaged installs
    ];
    for (const configPath of candidates) {
        try { if (fs.existsSync(configPath)) return configPath; } catch (e) {}
    }
    return candidates[candidates.length - 1];
}

ipcMain.handle('get-config', () => {
    try {
        const configPath = resolveConfigPath();
        if (fs.existsSync(configPath)) {
            return JSON.parse(fs.readFileSync(configPath, 'utf8'));
        }
    } catch (e) {
        console.error('Config read failed:', e);
    }
    return {};
});

ipcMain.on('save-config', (event, newConfig) => {
    try {
        const configPath = resolveConfigPath();
        fs.mkdirSync(path.dirname(configPath), { recursive: true });
        fs.writeFileSync(configPath, JSON.stringify(newConfig, null, 4));
    } catch (e) {
        console.error('Config write failed:', e);
    }
});

ipcMain.handle('get-preload-path', () => {
    return 'file://' + path.join(__dirname, 'webview-preload.js');
});

// --- Local Favicon Cache -----------------------------------------------------
// Fetches service icons once, caches them as data URLs in userData so the
// sidebar never leaks browsing habits to third-party icon services (Google).
const FAVICON_TTL = 7 * 24 * 60 * 60 * 1000; // 7 days
const faviconCachePath = () => path.join(app.getPath('userData'), 'favicon-cache.json');
let faviconCache = null;

function loadFaviconCache() {
    if (!faviconCache) {
        try { faviconCache = JSON.parse(fs.readFileSync(faviconCachePath(), 'utf8')); }
        catch (e) { faviconCache = {}; }
    }
    return faviconCache;
}

function persistFaviconCache() {
    try { fs.writeFileSync(faviconCachePath(), JSON.stringify(faviconCache)); } catch (e) {}
}

ipcMain.handle('get-favicon', async (event, domain) => {
    if (!domain || typeof domain !== 'string' || !/^[a-z0-9.-]+$/i.test(domain)) return null;

    const cache = loadFaviconCache();
    const entry = cache[domain];
    if (entry && entry.data && entry.ts && (Date.now() - entry.ts) < FAVICON_TTL) {
        return entry.data;
    }

    const candidates = [
        `https://${domain}/favicon.ico`,
        `https://icons.duckduckgo.com/ip3/${domain}.ico`
    ];

    for (const url of candidates) {
        try {
            const res = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(5000) });
            if (!res.ok) continue;
            const type = (res.headers.get('content-type') || '').split(';')[0].trim();
            if (!type.startsWith('image/')) continue;
            const buf = Buffer.from(await res.arrayBuffer());
            if (buf.length === 0 || buf.length > 200 * 1024) continue;

            const dataUrl = `data:${type};base64,${buf.toString('base64')}`;
            cache[domain] = { data: dataUrl, ts: Date.now() };
            persistFaviconCache();
            return dataUrl;
        } catch (e) { /* try next candidate */ }
    }
    return null;
});
// -----------------------------------------------------------------------------

ipcMain.on('update-badge', (event, count) => {
    if (app.setBadgeCount) app.setBadgeCount(count);
    if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.setTitle(count > 0 ? `WebSpace (${count})` : 'WebSpace');
    }
    if (tray) tray.setToolTip(count > 0 ? `WebSpace (${count} unread)` : 'WebSpace');
});

// Native Desktop Notification via D-Bus / libnotify
ipcMain.on('show-notification', (event, { title, body, appName }) => {
    if (Notification.isSupported()) {
        const notif = new Notification({
            title: title || appName || 'WebSpace',
            body: body || 'New notification',
            urgency: 'normal'
        });
        notif.on('click', () => {
            if (mainWindow) {
                if (mainWindow.isMinimized()) mainWindow.restore();
                mainWindow.show();
                mainWindow.focus();
            }
        });
        notif.show();
    }
});

// Permissions are remembered per-session so users aren't spammed with dialogs
const permissionMemory = new Map();
const PERM_LABELS = {
    media: 'camera & microphone',
    'display-capture': 'your screen',
    geolocation: 'your location',
    notifications: 'desktop notifications',
    clipboard_read: 'read your clipboard',
    'clipboard-read': 'read your clipboard',
    midi: 'MIDI devices',
    midiSysex: 'MIDI devices',
    idleDetection: 'idle detection'
};
// Low-risk permissions granted without prompting
const PERM_AUTO_ALLOW = new Set(['fullscreen', 'pointerLock', 'clipboard-sanitized-write', 'idle-detection']);

ipcMain.on('setup-partition', (event, partitionName) => {
    const ses = session.fromPartition(partitionName);

    ses.setPermissionRequestHandler((webContents, permission, callback, details) => {
        let urlHost = 'unknown';
        try { urlHost = new URL(details.requestingUrl).host; } catch (e) {}

        if (PERM_AUTO_ALLOW.has(permission)) return callback(true);

        const memKey = `${urlHost}:${permission}`;
        if (permissionMemory.has(memKey)) return callback(permissionMemory.get(memKey));

        const label = PERM_LABELS[permission] || permission;
        dialog.showMessageBox(mainWindow, {
            type: 'question',
            buttons: ['Allow', 'Deny'],
            defaultId: 0,
            cancelId: 1,
            noLink: true,
            title: 'Permission Request',
            message: `The website '${urlHost}' wants to access ${label}.`,
            detail: 'You can remember this choice for the current session.',
            checkboxLabel: 'Remember this choice for this session'
        }).then(({ response, checkboxChecked }) => {
            const allowed = response === 0;
            if (checkboxChecked) permissionMemory.set(memKey, allowed);
            callback(allowed);
        }).catch(() => callback(false));
    });

    // Actively reject native WebAuthn/FIDO2 prompts so they don't hang the UI and force Microsoft to fallback.
    ses.on('select-webauthn-account', (event, details, callback) => {
        event.preventDefault();
        callback(); // Cancels the request
    });
});

app.on('web-contents-created', (event, contents) => {
    // Webview guests get their own input stream — hook them up too
    if (contents.getType() === 'webview') {
        contents.on('before-input-event', handleGlobalShortcut);
    }

    contents.setWindowOpenHandler(({ url }) => {
        // Allow all popups to open as new windows natively.
        // We MUST inject the preload script into the popup so that Microsoft
        // cannot access WebAuthn or Electron APIs in the new window!
        return { 
            action: 'allow',
            overrideBrowserWindowOptions: {
                webPreferences: {
                    preload: path.join(__dirname, 'webview-preload.js'),
                    nodeIntegration: false,
                    contextIsolation: true
                }
            }
        };
    });

    // Block in-place navigation to non-web schemes (file:, javascript:, etc.)
    contents.on('will-navigate', (e, url) => {
        if (!/^https?:|^about:blank/.test(url) && contents.getType() === 'webview') e.preventDefault();
    });
});

// --- App UI Settings (theme / accent / hibernation) ---
const settingsPath = () => path.join(app.getPath('userData'), 'settings.json');
const DEFAULT_UI_SETTINGS = { theme: 'dark', accent: '#0078D7', hibernateMinutes: 20 };

ipcMain.handle('get-settings', () => {
    try {
        if (fs.existsSync(settingsPath())) {
            return { ...DEFAULT_UI_SETTINGS, ...JSON.parse(fs.readFileSync(settingsPath(), 'utf8')) };
        }
    } catch (e) { console.error('Settings read failed:', e); }
    return { ...DEFAULT_UI_SETTINGS };
});

ipcMain.handle('save-settings', (event, settings) => {
    try {
        fs.writeFileSync(settingsPath(), JSON.stringify({ ...DEFAULT_UI_SETTINGS, ...settings }, null, 2));
        return { success: true };
    } catch (e) {
        return { success: false, error: e.message };
    }
});

ipcMain.handle('clipboard-write', (event, text) => {
    try { clipboard.writeText(String(text)); return { success: true }; }
    catch (e) { return { success: false, error: e.message }; }
});

// --- Credential Vault Handlers ---
const getCredentialsPath = () => path.join(app.getPath('userData'), 'vault.json');

ipcMain.handle('save-credential', async (event, { appName, username, password }) => {
    if (!safeStorage.isEncryptionAvailable()) {
        return { success: false, error: 'OS Encryption not available on this system' };
    }
    
    try {
        const encryptedPassword = safeStorage.encryptString(password).toString('base64');
        const vaultPath = getCredentialsPath();
        
        let vault = {};
        if (fs.existsSync(vaultPath)) {
            vault = JSON.parse(fs.readFileSync(vaultPath, 'utf8'));
        }
        
        vault[appName] = { username, password: encryptedPassword };
        fs.writeFileSync(vaultPath, JSON.stringify(vault, null, 2));
        
        return { success: true };
    } catch (e) {
        return { success: false, error: e.message };
    }
});

ipcMain.handle('get-credential', async (event, appName) => {
    try {
        const vaultPath = getCredentialsPath();
        if (!fs.existsSync(vaultPath)) return null;
        
        const vault = JSON.parse(fs.readFileSync(vaultPath, 'utf8'));
        if (!vault[appName]) return null;
        
        const encryptedBuffer = Buffer.from(vault[appName].password, 'base64');
        const decryptedPassword = safeStorage.decryptString(encryptedBuffer);
        
        return { username: vault[appName].username, password: decryptedPassword };
    } catch (e) {
        return null; // Silent fail on decryption errors
    }
});

// List stored entries (passwords stay hidden until explicitly revealed/copied)
ipcMain.handle('list-credentials', () => {
    try {
        const vaultPath = getCredentialsPath();
        if (!fs.existsSync(vaultPath)) return [];
        const vault = JSON.parse(fs.readFileSync(vaultPath, 'utf8'));
        return Object.entries(vault).map(([appName, v]) => ({ appName, username: v.username || '' }));
    } catch (e) {
        return [];
    }
});

ipcMain.handle('delete-credential', (event, appName) => {
    try {
        const vaultPath = getCredentialsPath();
        if (!fs.existsSync(vaultPath)) return { success: true };
        const vault = JSON.parse(fs.readFileSync(vaultPath, 'utf8'));
        delete vault[appName];
        fs.writeFileSync(vaultPath, JSON.stringify(vault, null, 2));
        return { success: true };
    } catch (e) {
        return { success: false, error: e.message };
    }
});
// ---------------------------------
