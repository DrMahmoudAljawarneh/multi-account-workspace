const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
    getWebviewPreloadPath: () => ipcRenderer.invoke('get-preload-path'),
    getConfig: () => ipcRenderer.invoke('get-config'),
    setupPartition: (partition) => ipcRenderer.send('setup-partition', partition),
    saveConfig: (config) => ipcRenderer.send('save-config', config),
    updateBadge: (count) => ipcRenderer.send('update-badge', count),
    showNotification: (data) => ipcRenderer.send('show-notification', data),
    minimizeWindow: () => ipcRenderer.send('window-minimize'),
    maximizeWindow: () => ipcRenderer.send('window-maximize'),
    closeWindow: () => ipcRenderer.send('window-close'),

    // Global shortcuts intercepted by main process (work while webviews are focused)
    onGlobalShortcut: (cb) => ipcRenderer.on('global-shortcut', (_event, cmd) => cb(cmd)),

    // Local cached favicon lookup (no third-party tracking)
    getFavicon: (domain) => ipcRenderer.invoke('get-favicon', domain),

    // App UI settings (theme / accent / hibernation)
    getSettings: () => ipcRenderer.invoke('get-settings'),
    saveSettings: (settings) => ipcRenderer.invoke('save-settings', settings),
    writeClipboard: (text) => ipcRenderer.invoke('clipboard-write', text),

    // Credential Vault
    saveCredential: (data) => ipcRenderer.invoke('save-credential', data),
    getCredential: (appName) => ipcRenderer.invoke('get-credential', appName),
    listCredentials: () => ipcRenderer.invoke('list-credentials'),
    deleteCredential: (appName) => ipcRenderer.invoke('delete-credential', appName)
});
