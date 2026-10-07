const sidebar = document.getElementById('sidebar');
const leftStack = document.getElementById('left-stack');
const rightStack = document.getElementById('right-stack');
const divider = document.getElementById('divider');
const loadingBar = document.getElementById('loading-bar');

let isSplit = false;
let activePane = 'left';
let webviews = [];

// Linux Window Controls
document.getElementById('win-min').onclick = () => window.api.minimizeWindow();
document.getElementById('win-max').onclick = () => window.api.maximizeWindow();
document.getElementById('win-close').onclick = () => window.api.closeWindow();

// Toast Notifications
function showToast(message, icon = 'ℹ️') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.innerHTML = `<span>${icon}</span> <span>${message}</span>`;
    container.appendChild(toast);
    
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 250);
    }, 3200);
}

// Pane Selection
function setPane(pane) {
    activePane = pane;
    document.getElementById('left-pane').classList.toggle('active-pane', pane === 'left');
    document.getElementById('right-pane').classList.toggle('active-pane', pane === 'right');
}
document.getElementById('left-pane').addEventListener('mousedown', () => setPane('left'));
document.getElementById('right-pane').addEventListener('mousedown', () => setPane('right'));

// Drag Divider
let isDragging = false;
divider.addEventListener('mousedown', (e) => {
    isDragging = true;
    divider.classList.add('dragging');
    document.body.style.cursor = 'col-resize';
});
document.addEventListener('mousemove', (e) => {
    if (!isDragging || !isSplit) return;
    const workspaces = document.getElementById('workspaces');
    const leftWidth = ((e.clientX - sidebar.getBoundingClientRect().width) / workspaces.clientWidth) * 100;
    if (leftWidth > 15 && leftWidth < 85) {
        document.getElementById('left-pane').style.flex = `0 0 ${leftWidth}%`;
        document.getElementById('right-pane').style.flex = `1 1 0%`;
    }
});
document.addEventListener('mouseup', () => {
    if (isDragging) {
        isDragging = false;
        divider.classList.remove('dragging');
        document.body.style.cursor = 'default';
    }
});

// Lazy Mount with Background Throttling for Linux
function mountWebview(appObj) {
    if (!appObj.wv) {
        showToast(`Starting ${appObj.app.name}...`, '🚀');
        const wv = document.createElement('webview');
        // Partition must be set before src (first navigation locks the session)
        wv.setAttribute('partition', `persist:${appObj.profileName}`);
        wv.setAttribute('allowpopups', ''); // required for "Sign in with Google" popups
        // 100% Solution: We must also override the DOM UA, otherwise navigator.userAgent 
        // exposes "Electron" to Google's JavaScript engine inside the webview!
        wv.setAttribute('useragent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0');
        wv.style.display = 'none';
        window.api.setupPartition(wv.partition);
        wv.setAttribute('src', appObj.app.url);
        
        wv.addEventListener('dom-ready', () => {
            if (appObj.app.customCSS) wv.insertCSS(appObj.app.customCSS);
        });
        
        wv.addEventListener('did-start-loading', () => {
            if (wv.style.display === 'flex') {
                loadingBar.style.opacity = '1';
                loadingBar.style.width = '35%';
            }
        });
        wv.addEventListener('did-stop-loading', () => {
            if (wv.style.display === 'flex') {
                loadingBar.style.width = '100%';
                setTimeout(() => { loadingBar.style.opacity = '0'; setTimeout(() => loadingBar.style.width = '0%', 250); }, 250);
            }
        });
        
        appObj.wv = wv;
        leftStack.appendChild(wv);
    }
    appObj.lastAccessed = Date.now();
    return appObj.wv;
}

async function init() {
    const config = await window.api.getConfig();

    for (const [profile, apps] of Object.entries(config)) {
        const header = document.createElement('div');
        header.className = 'sidebar-header';
        header.textContent = `━━ ${profile.toUpperCase()} ━━`;
        sidebar.appendChild(header);

        apps.forEach((app) => {
            const item = document.createElement('div');
            item.className = 'sidebar-item';
            
            const domain = new URL(app.url).hostname;
            const iconUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=64`;
            
            item.innerHTML = `<img src="${iconUrl}" width="22" height="22" style="margin-right:10px; border-radius:4px; flex-shrink:0;"> <span class="sidebar-text" style="transition: opacity 0.2s;">${app.name}</span>`;
            sidebar.appendChild(item);

            const appObj = { item, wv: null, app, profileName: profile, lastAccessed: 0, lastBadge: 0 };
            webviews.push(appObj);

            item.addEventListener('click', () => {
                document.querySelectorAll('.sidebar-item').forEach(el => el.classList.remove('active'));
                item.classList.add('active');
                
                const wv = mountWebview(appObj);
                const targetStack = activePane === 'left' ? leftStack : rightStack;
                
                Array.from(targetStack.children).forEach(el => el.style.display = 'none');
                
                if (wv.parentElement !== targetStack) {
                    wv.parentElement.removeChild(wv);
                    targetStack.appendChild(wv);
                }
                wv.style.display = 'flex';
                
                loadingBar.style.opacity = '1';
                loadingBar.style.width = '100%';
                setTimeout(() => { loadingBar.style.opacity = '0'; setTimeout(() => loadingBar.style.width = '0%', 250); }, 200);
            });
        });
    }

    if (webviews.length > 0) webviews[0].item.click();
    
    // Background Tasks: Badging, Native Notifications & Hibernation
    setInterval(() => {
        let totalUnread = 0;
        const now = Date.now();
        
        webviews.forEach(obj => {
            // Hibernation check (20 mins idle)
            if (obj.wv && obj.wv.style.display !== 'flex' && (now - obj.lastAccessed > 1200000)) {
                obj.wv.remove();
                obj.wv = null;
                showToast(`Hibernated ${obj.app.name} to save memory`, '💤');
            }
            
            // Badge extraction
            try {
                if (obj.wv) {
                    const title = obj.wv.getTitle();
                    const match = title.match(/^\((\d+)\)/);
                    let badgeNum = 0;
                    let badgeStr = "";
                    
                    if (match) {
                        badgeNum = parseInt(match[1]);
                        totalUnread += badgeNum;
                        badgeStr = `[${badgeNum}] `;
                    } else if (title.startsWith('*')) {
                        badgeNum = 1;
                        totalUnread += 1;
                        badgeStr = `[•] `;
                    }
                    
                    // Dispatch Native Linux Notification on new message
                    if (badgeNum > obj.lastBadge && obj.wv.style.display !== 'flex') {
                        window.api.showNotification({
                            title: obj.app.name,
                            body: `You have new messages in ${obj.app.name}`,
                            appName: obj.app.name
                        });
                    }
                    obj.lastBadge = badgeNum;
                    
                    const txtSpan = obj.item.querySelector('.sidebar-text');
                    txtSpan.textContent = badgeStr + obj.app.name;
                }
            } catch(e) {}
        });
        window.api.updateBadge(totalUnread);
    }, 2000);
}

init();

// Command Palette
const paletteOverlay = document.getElementById('palette-overlay');
const paletteInput = document.getElementById('palette-input');
const paletteResults = document.getElementById('palette-results');
let paletteOptions = [];
let paletteIdx = 0;

function openPalette() {
    paletteOptions = webviews.map(w => ({ name: `Switch to ${w.app.name}`, action: () => w.item.click(), icon: '🔍' }));
    paletteOptions.push({ name: 'Toggle Split View', action: () => document.getElementById('btn-split').click(), icon: '◫' });
    paletteOptions.push({ name: 'Toggle Sidebar', action: () => document.getElementById('btn-toggle-sidebar').click(), icon: '☰' });
    paletteOptions.push({ name: 'Open Settings', action: () => document.getElementById('btn-settings').click(), icon: '⚙️' });
    paletteOptions.push({ name: 'Reload Active Tab', action: () => document.getElementById('btn-reload').click(), icon: '↻' });
    
    paletteOverlay.classList.add('show');
    paletteInput.value = '';
    renderPalette();
    paletteInput.focus();
}
function closePalette() { paletteOverlay.classList.remove('show'); }
function renderPalette() {
    const q = paletteInput.value.toLowerCase();
    const filtered = paletteOptions.filter(o => o.name.toLowerCase().includes(q));
    paletteResults.innerHTML = '';
    paletteIdx = Math.min(paletteIdx, Math.max(0, filtered.length - 1));
    
    filtered.forEach((opt, idx) => {
        const el = document.createElement('div');
        el.className = `palette-item ${idx === paletteIdx ? 'selected' : ''}`;
        el.innerHTML = `<span>${opt.icon}</span> <span>${opt.name}</span>`;
        el.onmouseover = () => { paletteIdx = idx; renderPalette(); };
        el.onclick = () => { closePalette(); opt.action(); };
        paletteResults.appendChild(el);
    });
}
paletteInput.addEventListener('input', renderPalette);
paletteInput.addEventListener('keydown', (e) => {
    const items = paletteResults.children;
    if (e.key === 'ArrowDown') { e.preventDefault(); paletteIdx = (paletteIdx + 1) % items.length; renderPalette(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); paletteIdx = (paletteIdx - 1 + items.length) % items.length; renderPalette(); }
    if (e.key === 'Enter' && items.length > 0) { items[paletteIdx].click(); }
    if (e.key === 'Escape') { closePalette(); }
});
paletteOverlay.addEventListener('click', (e) => { if(e.target === paletteOverlay) closePalette(); });

// Keyboard Shortcuts
window.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key >= '1' && e.key <= '9') {
        const idx = parseInt(e.key) - 1;
        if (idx < webviews.length) webviews[idx].item.click();
    }
    if (e.ctrlKey && e.key.toLowerCase() === 'b') document.getElementById('btn-toggle-sidebar').click();
    if (e.ctrlKey && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); }
});

// Toolbar buttons
document.getElementById('btn-toggle-sidebar').onclick = () => sidebar.classList.toggle('collapsed');
document.getElementById('btn-split').onclick = () => {
    isSplit = !isSplit;
    document.getElementById('right-pane').style.display = isSplit ? 'flex' : 'none';
    divider.style.display = isSplit ? 'block' : 'none';
    
    if (!isSplit) {
        document.getElementById('left-pane').style.flex = '1 1 0%';
        Array.from(rightStack.children).forEach(child => {
            child.style.display = 'none';
            leftStack.appendChild(child);
        });
        setPane('left');
        showToast('Split View disabled', '🔲');
    } else {
        showToast('Split View active (drag center divider)', '◫');
    }
};

function getActiveWebview() {
    const stack = activePane === 'left' ? leftStack : rightStack;
    return Array.from(stack.children).find(wv => wv.style.display === 'flex');
}

document.getElementById('btn-back').onclick = () => { const wv = getActiveWebview(); if(wv) wv.goBack(); };
document.getElementById('btn-forward').onclick = () => { const wv = getActiveWebview(); if(wv) wv.goForward(); };
document.getElementById('btn-reload').onclick = () => { const wv = getActiveWebview(); if(wv) wv.reload(); };

// Settings Modal
const settingsModal = document.getElementById('settings-modal');
document.getElementById('btn-settings').onclick = async () => {
    const cfg = await window.api.getConfig();
    document.getElementById('config-editor').value = JSON.stringify(cfg, null, 4);
    settingsModal.classList.add('show');
};
document.getElementById('btn-cancel-settings').onclick = () => settingsModal.classList.remove('show');
document.getElementById('btn-save-settings').onclick = () => {
    try {
        const newCfg = JSON.parse(document.getElementById('config-editor').value);
        window.api.saveConfig(newCfg);
        settingsModal.classList.remove('show');
        showToast("Settings saved! Restarting app...", '✅');
        setTimeout(() => window.close(), 1400);
    } catch(err) {
        showToast("Invalid JSON syntax!", '❌');
    }
};
