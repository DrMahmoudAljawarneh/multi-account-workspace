const { app, BrowserWindow, ipcMain, session, dialog, shell, Tray, Menu, nativeImage, Notification } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Linux Performance & Wayland Optimizations
app.commandLine.appendSwitch('enable-features', 'UseOzonePlatform,WaylandWindowDecorations');
app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
app.commandLine.appendSwitch('disk-cache-size', '268435456'); // Cap disk cache to 256MB
app.commandLine.appendSwitch('disable-gpu'); // Safe fallback for Asahi/mesa software stacks

let mainWindow;
let tray;

app.whenReady().then(() => {
    mainWindow = new BrowserWindow({
        width: 1240,
        height: 820,
        minWidth: 800,
        minHeight: 600,
        frame: false, // Linux Custom Titlebar
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
        const emptyIcon = nativeImage.createEmpty();
        tray = new Tray(emptyIcon);
        const contextMenu = Menu.buildFromTemplate([
            { label: 'Show Workspace', click: () => { mainWindow.show(); mainWindow.focus(); } },
            { label: 'Toggle Fullscreen', click: () => mainWindow.setFullScreen(!mainWindow.isFullScreen()) },
            { type: 'separator' },
            { label: 'Quit', click: () => app.quit() }
        ]);
        tray.setToolTip('Workspace');
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
    if (tray) tray.setToolTip(count > 0 ? `Workspace (${count} unread)` : 'Workspace');
});

// Native Desktop Notification via D-Bus / libnotify
ipcMain.on('show-notification', (event, { title, body, appName }) => {
    if (Notification.isSupported()) {
        const notif = new Notification({
            title: title || appName || 'Workspace',
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
        if (url.startsWith('http')) {
            shell.openExternal(url);
        }
        return { action: 'deny' };
    });
});
