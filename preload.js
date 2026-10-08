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
    
    // Credential Vault
    saveCredential: (data) => ipcRenderer.invoke('save-credential', data),
    getCredential: (appName) => ipcRenderer.invoke('get-credential', appName)
});
