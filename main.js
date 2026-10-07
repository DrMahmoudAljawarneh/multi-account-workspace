const { app, BrowserWindow, ipcMain, session, dialog, shell, Tray, Menu, nativeImage, Notification } = require('electron');
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
app.commandLine.appendSwitch('disable-features', 'UserAgentClientHint');

// --- Google Sign-In & Bot-Detection Bypass ------------------------------------
const FIREFOX_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0';
app.userAgentFallback = FIREFOX_UA;

const AUTH_HOSTS = [
    'accounts.google.com',
    'accounts.youtube.com',
    'myaccount.google.com',
    'login.microsoftonline.com',
    'login.live.com',
    'appleid.apple.com'
];
function isAuthUrl(url) {
    try {
        const { protocol, hostname } = new URL(url);
        return protocol === 'https:' && AUTH_HOSTS.some(h => hostname === h || hostname.endsWith('.' + h));
    } catch (e) {
        return false;
    }
}

function hardenSession(ses) {
    ses.setUserAgent(FIREFOX_UA);
    ses.webRequest.onBeforeSendHeaders((details, callback) => {
        const headers = details.requestHeaders;
        headers['User-Agent'] = FIREFOX_UA;
        // Strip out all Client Hints so Google doesn't detect Chromium mismatch
        for (const key of Object.keys(headers)) {
            const lower = key.toLowerCase();
            if (lower.startsWith('sec-ch-ua')) {
                delete headers[key];
            }
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
});

app.on('web-contents-created', (event, contents) => {
    contents.setWindowOpenHandler(({ url }) => {
        // Allow all popups to open as new windows inside the Electron app natively.
        // This stops them from escaping to the system browser and ensures they
        // inherit the session and headers of the parent window.
        return {
            action: 'allow',
            overrideBrowserWindowOptions: {
                parent: mainWindow,
                autoHideMenuBar: true,
                webPreferences: {
                    nodeIntegration: false,
                    contextIsolation: true,
                    sandbox: true,
                    preload: path.join(__dirname, 'webview-preload.js')
                }
            }
        };
    });

    // Block in-place navigation to non-web schemes (file:, javascript:, etc.)
    contents.on('will-navigate', (e, url) => {
        if (!/^https?:|^about:blank/.test(url) && contents.getType() === 'webview') e.preventDefault();
    });
});
