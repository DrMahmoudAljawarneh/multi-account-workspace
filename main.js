const { app, BrowserWindow, ipcMain, session, dialog, shell, Tray, Menu, nativeImage, Notification, safeStorage } = require('electron');
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

// Config lookup
ipcMain.handle('get-config', () => {
    const paths = [
        path.join(os.homedir(), 'newapp', 'config.json'),
        path.join(os.homedir(), '.my_webapp_data', 'config.json'),
        path.join(__dirname, '..', 'config.json')
    ];
    for (const configPath of paths) {
        if (fs.existsSync(configPath)) {
            return JSON.parse(fs.readFileSync(configPath, 'utf8'));
        }
    }
    return {};
});

ipcMain.on('save-config', (event, newConfig) => {
    const configPath = path.join(os.homedir(), 'newapp', 'config.json');
    fs.writeFileSync(configPath, JSON.stringify(newConfig, null, 4));
});

ipcMain.handle('get-preload-path', () => {
    return 'file://' + path.join(__dirname, 'webview-preload.js');
});

ipcMain.on('update-badge', (event, count) => {
    if (app.setBadgeCount) app.setBadgeCount(count);
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

ipcMain.on('setup-partition', (event, partitionName) => {
    const ses = session.fromPartition(partitionName);
    
    // Clear cache periodic protection
    ses.setPermissionRequestHandler((webContents, permission, callback, details) => {
        let urlHost = "unknown";
        try { urlHost = new URL(details.requestingUrl).host; } catch (e) {}
        const choice = dialog.showMessageBoxSync(mainWindow, {
            type: 'question',
            buttons: ['Allow', 'Deny'],
            title: 'Permission Request',
            message: `The website '${urlHost}' wants to access your ${permission}.\n\nDo you want to allow this?`
        });
        callback(choice === 0);
    });

    // Actively reject native WebAuthn/FIDO2 prompts so they don't hang the UI and force Microsoft to fallback.
    ses.on('select-webauthn-account', (event, details, callback) => {
        event.preventDefault();
        callback(); // Cancels the request
    });
});

app.on('web-contents-created', (event, contents) => {
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
// ---------------------------------
