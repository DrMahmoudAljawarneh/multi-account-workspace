const sidebar = document.getElementById('sidebar');
const sidebarList = document.getElementById('sidebar-list');
const leftStack = document.getElementById('left-stack');
const rightStack = document.getElementById('right-stack');
const divider = document.getElementById('divider');
const loadingBar = document.getElementById('loading-bar');

let isSplit = false;
let activePane = 'left';
let webviews = [];
let activeApp = null;
let preloadPath = null;

// Linux Window Controls
document.getElementById('win-min').onclick = () => window.api.minimizeWindow();
document.getElementById('win-max').onclick = () => window.api.maximizeWindow();
document.getElementById('win-close').onclick = () => window.api.closeWindow();

// Toast Notifications (optional action button, e.g. "Retry")
function showToast(message, icon = 'ℹ️', action = null) {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = 'toast';

    const iconEl = document.createElement('span');
    iconEl.className = 'toast-icon';
    iconEl.textContent = icon;
    const msgEl = document.createElement('span');
    msgEl.textContent = message;
    toast.append(iconEl, msgEl);

    if (action) {
        const btn = document.createElement('button');
        btn.className = 'toast-action';
        btn.textContent = action.label;
        btn.onclick = () => { action.onClick(); toast.remove(); };
        toast.appendChild(btn);
    }

    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 250);
    }, action ? 6000 : 3200);
}

// ---------- Loading pulse ----------
let progressGen = 0;

function startProgress() {
    const gen = ++progressGen;
    loadingBar.style.transition = 'width 1.4s ease, opacity 0.3s ease';
    loadingBar.style.opacity = '1';
    loadingBar.style.width = '70%';
    return gen;
}
function endProgress() {
    ++progressGen;
    loadingBar.style.transition = 'width 0.2s ease, opacity 0.3s ease';
    loadingBar.style.width = '100%';
    const gen = progressGen;
    setTimeout(() => {
        if (gen !== progressGen) return;
        loadingBar.style.opacity = '0';
        setTimeout(() => { if (gen === progressGen) loadingBar.style.width = '0%'; }, 300);
    }, 220);
}
function beginFakeProgress() {
    const gen = ++progressGen;
    loadingBar.style.transition = 'width 0.35s ease, opacity 0.3s ease';
    loadingBar.style.opacity = '1';
    loadingBar.style.width = '60%';
    setTimeout(() => { if (gen === progressGen) endProgress(); }, 450);
}

// Pane Selection
function setPane(pane) {
    activePane = pane;
    document.getElementById('left-pane').classList.toggle('active-pane', pane === 'left');
    document.getElementById('right-pane').classList.toggle('active-pane', pane === 'right');
    updateNavState();
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
        document.getElementById('right-pane').style.flex = '1 1 0%';
    }
});
document.addEventListener('mouseup', () => {
    if (isDragging) {
        isDragging = false;
        divider.classList.remove('dragging');
        document.body.style.cursor = 'default';
    }
});

// ---------- Webview lifecycle ----------

function isVisible(wv) { return !!wv && wv.style.display === 'flex'; }

function syncActiveStates() {
    webviews.forEach(o => o.item.classList.toggle('active', isVisible(o.wv)));
}

function markLoadError(appObj, description) {
    appObj.item.classList.add('error');
    const now = Date.now();
    if (now - (appObj.lastErrorAt || 0) < 3000) return; // debounce repeated failures
    appObj.lastErrorAt = now;

    if (isVisible(appObj.wv)) {
        showToast(`${appObj.app.name} failed to load: ${description}`, '⚠️', {
            label: 'Retry',
            onClick: () => {
                if (appObj.wv) {
                    appObj.item.classList.remove('error');
                    appObj.wv.reload();
                }
            }
        });
    }
}

function hibernateApp(appObj) {
    if (!appObj.wv) return;
    if (isVisible(appObj.wv)) return; // never blank out a visible pane
    appObj.wv.remove();
    appObj.wv = null;
    appObj.item.classList.remove('mounted');
    appObj.item.classList.add('hibernated');
    appObj.item.classList.remove('error');
    syncActiveStates();
}

// Lazy Mount — preload & partition are attached BEFORE src so the first
// navigation is already covered by the spoofing/injection layer.
function mountWebview(appObj, targetStack) {
    if (!appObj.wv) {
        const wv = document.createElement('webview');
        wv.setAttribute('partition', `persist:${appObj.profileName}`);
        wv.setAttribute('allowpopups', ''); // required for "Sign in with Google" popups
        if (preloadPath) wv.setAttribute('preload', preloadPath);
        wv.style.display = 'none';
        window.api.setupPartition(wv.partition);

        wv.addEventListener('dom-ready', async () => {
            if (appObj.app.customCSS) wv.insertCSS(appObj.app.customCSS);

            // Auto-Login Script Injection (values JSON-stringified to survive quotes)
            if (window.api.getCredential) {
                try {
                    const cred = await window.api.getCredential(appObj.app.name);
                    if (cred && cred.username && cred.password) {
                        const injectionScript = `
                            (function() {
                                const USER = ${JSON.stringify(String(cred.username))};
                                const PASS = ${JSON.stringify(String(cred.password))};
                                const tryFill = () => {
                                    const emailInput = document.querySelector('input[type="email"], input[name="loginfmt"], input[name="identifier"]');
                                    const passInput = document.querySelector('input[type="password"]');
                                    let filled = false;
                                    if (emailInput && !emailInput.value) {
                                        emailInput.value = USER;
                                        emailInput.dispatchEvent(new Event('input', { bubbles: true }));
                                        filled = true;
                                    }
                                    if (passInput && !passInput.value) {
                                        passInput.value = PASS;
                                        passInput.dispatchEvent(new Event('input', { bubbles: true }));
                                        filled = true;
                                    }
                                    return filled;
                                };
                                const interval = setInterval(() => {
                                    if (tryFill()) {
                                        console.log('WebSpace: Auto-filled credentials from Secure Vault');
                                        clearInterval(interval);
                                    }
                                }, 500);
                                setTimeout(() => clearInterval(interval), 10000);
                            })();
                        `;
                        wv.executeJavaScript(injectionScript).catch(e => console.error('Auto-fill error:', e));
                    }
                } catch (e) { /* vault read failure must never break loading */ }
            }
        });

        wv.addEventListener('did-start-loading', () => {
            if (isVisible(wv)) startProgress();
        });
        wv.addEventListener('did-stop-loading', () => {
            if (isVisible(wv)) endProgress();
            updateNavState();
        });
        wv.addEventListener('did-navigate', () => {
            appObj.item.classList.remove('error');
            updateNavState();
        });
        wv.addEventListener('did-navigate-in-page', updateNavState);
        wv.addEventListener('did-fail-load', (e) => {
            if (!e.isMainFrame || e.errorCode === -3) return; // ignore aborted loads & subframes
            markLoadError(appObj, e.errorDescription || `error ${e.errorCode}`);
        });
        wv.addEventListener('render-process-gone', () => markLoadError(appObj, 'renderer process crashed'));

        wv.setAttribute('src', appObj.app.url);
        targetStack.appendChild(wv);
        appObj.wv = wv;
        appObj.item.classList.remove('hibernated');
        appObj.item.classList.add('mounted');
    }
    appObj.lastAccessed = Date.now();
    return appObj.wv;
}

function activateApp(appObj) {
    activeApp = appObj;
    const targetStack = activePane === 'left' ? leftStack : rightStack;

    const wv = mountWebview(appObj, targetStack);
    if (wv.parentElement !== targetStack) targetStack.appendChild(wv);

    Array.from(targetStack.children).forEach(el => {
        el.style.display = el === wv ? 'flex' : 'none';
    });

    syncActiveStates();
    beginFakeProgress();
    updateNavState();
}

function getActiveWebview() {
    const stack = activePane === 'left' ? leftStack : rightStack;
    return Array.from(stack.children).find(el => el.tagName === 'WEBVIEW' && el.style.display === 'flex');
}

function updateNavState() {
    const wv = getActiveWebview();
    let back = false, fwd = false;
    try { if (wv) { back = wv.canGoBack(); fwd = wv.canGoForward(); } } catch (e) {}
    document.getElementById('btn-back').classList.toggle('disabled', !back);
    document.getElementById('btn-forward').classList.toggle('disabled', !fwd);
}

// ---------- Sidebar rendering ----------

const MOON_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>';

function renderSidebar(config) {
    sidebarList.innerHTML = '';
    webviews = [];

    for (const [profile, apps] of Object.entries(config)) {
        const header = document.createElement('div');
        header.className = 'sidebar-header';
        header.textContent = profile;
        sidebarList.appendChild(header);

        (Array.isArray(apps) ? apps : []).forEach((app) => {
            const item = document.createElement('div');
            item.className = 'sidebar-item';
            item.tabIndex = 0;

            item.innerHTML =
                '<span class="app-tile"><span class="tile-letter"></span></span>' +
                '<span class="sidebar-text app-name"></span>' +
                '<span class="badge"></span>' +
                `<button class="item-action" title="Hibernate now">${MOON_SVG}</button>`;

            item.querySelector('.tile-letter').textContent = (app.name || '?').charAt(0).toUpperCase();
            item.querySelector('.app-name').textContent = app.name;
            const shortcutIdx = webviews.length;
            item.title = shortcutIdx < 9 ? `${app.name} — Ctrl+${shortcutIdx + 1}` : app.name;
            sidebarList.appendChild(item);

            const appObj = {
                item,
                badgeEl: item.querySelector('.badge'),
                wv: null,
                app,
                profileName: profile,
                lastAccessed: 0,
                lastBadge: 0,
                faviconUrl: null
            };
            webviews.push(appObj);

            item.addEventListener('click', () => activateApp(appObj));
            item.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); activateApp(appObj); }
            });
            item.querySelector('.item-action').addEventListener('click', (e) => {
                e.stopPropagation();
                hibernateApp(appObj);
            });

            // Fetch icon from local cache (falls back to the letter tile)
            let domain = null;
            try { domain = new URL(app.url).hostname; } catch (e) {}
            if (domain && window.api.getFavicon) {
                window.api.getFavicon(domain).then(dataUrl => {
                    if (!dataUrl) return;
                    appObj.faviconUrl = dataUrl;
                    const img = new Image();
                    img.alt = '';
                    img.onload = () => {
                        img.classList.add('loaded');
                        item.querySelector('.app-tile').appendChild(img);
                    };
                    img.src = dataUrl;
                }).catch(() => {});
            }
        });
    }
}

// ---------- Background loop: badges, notifications & hibernation ----------

function startBackgroundLoop() {
    setInterval(() => {
        let totalUnread = 0;
        const now = Date.now();

        webviews.forEach(obj => {
            // Hibernation check (20 mins idle) — silent; the tile dims as feedback
            if (obj.wv && !isVisible(obj.wv) && (now - obj.lastAccessed > 1200000)) {
                hibernateApp(obj);
            }

            if (!obj.wv) return;
            try {
                const title = obj.wv.getTitle();
                const match = title.match(/^\((\d+)\)/);
                let badgeNum = 0;

                if (match) {
                    badgeNum = parseInt(match[1], 10);
                    totalUnread += badgeNum;
                } else if (title.startsWith('*')) {
                    badgeNum = 1;
                    totalUnread += 1;
                }

                // Dispatch Native notification on new message
                if (badgeNum > obj.lastBadge && !isVisible(obj.wv)) {
                    window.api.showNotification({
                        title: obj.app.name,
                        body: `You have new messages in ${obj.app.name}`,
                        appName: obj.app.name
                    });
                }
                obj.lastBadge = badgeNum;

                obj.badgeEl.textContent = badgeNum > 99 ? '99+' : String(badgeNum);
                obj.badgeEl.classList.toggle('show', badgeNum > 0);
            } catch (e) { /* webview not ready yet */ }
        });

        window.api.updateBadge(totalUnread);
    }, 2000);
}

// ---------- Init ----------

async function init() {
    try { preloadPath = await window.api.getWebviewPreloadPath(); } catch (e) {}
    const config = await window.api.getConfig();
    renderSidebar(config);
    if (webviews.length > 0) activateApp(webviews[0]);
    startBackgroundLoop();
}

init();

// ---------- Command Palette ----------

const paletteOverlay = document.getElementById('palette-overlay');
const paletteInput = document.getElementById('palette-input');
const paletteResults = document.getElementById('palette-results');
let paletteOptions = [];
let paletteIdx = 0;

function buildPaletteOptions() {
    paletteOptions = webviews.map(w => ({
        name: `Switch to ${w.app.name}`,
        iconHtml: w.faviconUrl
            ? `<img class="pal-icon" src="${w.faviconUrl}" alt="">`
            : `<span class="pal-icon">${(w.app.name || '?').charAt(0).toUpperCase()}</span>`,
        action: () => activateApp(w)
    }));

    const commands = [
        { name: 'Toggle Split View', icon: '◫', action: () => document.getElementById('btn-split').click() },
        { name: 'Toggle Sidebar', icon: '☰', action: () => document.getElementById('btn-toggle-sidebar').click() },
        { name: 'Open Settings', icon: '⚙️', action: () => document.getElementById('btn-settings').click() },
        { name: 'Open Vault', icon: '🔑', action: () => document.getElementById('btn-vault').click() },
        { name: 'Reload Active Tab', icon: '↻', action: () => document.getElementById('btn-reload').click() },
        {
            name: 'Hibernate all background apps',
            icon: '💤',
            action: () => {
                let count = 0;
                webviews.slice().forEach(o => {
                    if (o.wv && !isVisible(o.wv)) { hibernateApp(o); count++; }
                });
                showToast(count > 0 ? `Hibernated ${count} background app${count > 1 ? 's' : ''}` : 'No background apps to hibernate', '💤');
            }
        }
    ];
    commands.forEach(c => paletteOptions.push({
        name: c.name,
        iconHtml: `<span class="pal-icon emoji">${c.icon}</span>`,
        action: c.action
    }));
}

function openPalette() {
    if (paletteOverlay.classList.contains('show')) { closePalette(); return; }
    buildPaletteOptions();
    paletteOverlay.classList.add('show');
    paletteInput.value = '';
    paletteIdx = 0;
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
        el.innerHTML = `${opt.iconHtml}<span class="pal-name"></span>`;
        el.querySelector('.pal-name').textContent = opt.name;
        el.onmouseover = () => { paletteIdx = idx; renderPalette(); };
        el.onclick = () => { closePalette(); opt.action(); };
        paletteResults.appendChild(el);
    });
}
paletteInput.addEventListener('input', () => { paletteIdx = 0; renderPalette(); });
paletteInput.addEventListener('keydown', (e) => {
    const items = paletteResults.children;
    if (e.key === 'ArrowDown') { e.preventDefault(); if (items.length) paletteIdx = (paletteIdx + 1) % items.length; renderPalette(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); if (items.length) paletteIdx = (paletteIdx - 1 + items.length) % items.length; renderPalette(); }
    if (e.key === 'Enter' && items.length > 0) { items[paletteIdx].click(); }
    if (e.key === 'Escape') { closePalette(); }
});
paletteOverlay.addEventListener('click', (e) => { if (e.target === paletteOverlay) closePalette(); });
document.getElementById('palette-hint').addEventListener('click', openPalette);

// ---------- Keyboard shortcuts ----------
// The heavy chords (Ctrl+K / Ctrl+B / Ctrl+1-9 / Ctrl+Shift+S) are intercepted
// by the main process so they work even while a webview has focus, and arrive
// here over IPC. Renderer-side we only handle plain Escape for modals.

function handleGlobalShortcut(cmd) {
    if (cmd === 'palette') openPalette();
    else if (cmd === 'toggle-sidebar') sidebar.classList.toggle('collapsed');
    else if (cmd === 'toggle-split') document.getElementById('btn-split').click();
    else if (cmd === 'find') { /* Find-in-page arrives in Phase 3 */ }
    else if (cmd.startsWith('app:')) {
        const idx = parseInt(cmd.slice(4), 10) - 1;
        if (webviews[idx]) activateApp(webviews[idx]);
    }
}
if (window.api.onGlobalShortcut) window.api.onGlobalShortcut(handleGlobalShortcut);

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        const open = document.querySelector('.modal-overlay.show');
        if (open) open.classList.remove('show');
    }
});

// ---------- Vault Modal ----------

const btnVault = document.getElementById('btn-vault');
const vaultModal = document.getElementById('vault-modal');

btnVault.addEventListener('click', () => {
    vaultModal.classList.add('show');
    document.getElementById('vault-appname').value = activeApp ? activeApp.app.name : '';
    document.getElementById('vault-username').value = '';
    document.getElementById('vault-password').value = '';
    document.getElementById('vault-username').focus();
});

document.getElementById('btn-cancel-vault').addEventListener('click', () => vaultModal.classList.remove('show'));
document.getElementById('btn-save-vault').addEventListener('click', async () => {
    const btnSaveVault = document.getElementById('btn-save-vault');
    const appName = document.getElementById('vault-appname').value.trim();
    const username = document.getElementById('vault-username').value.trim();
    const password = document.getElementById('vault-password').value.trim();

    if (!appName || !username || !password) {
        showToast('Please fill all fields', '⚠️');
        return;
    }

    btnSaveVault.textContent = 'Encrypting...';
    btnSaveVault.disabled = true;

    try {
        const res = await window.api.saveCredential({ appName, username, password });
        if (res.success) {
            showToast(`Credentials saved securely for ${appName}`, '🔒');
            vaultModal.classList.remove('show');
        } else {
            showToast('Encryption failed: ' + res.error, '❌');
        }
    } catch (e) {
        showToast('Save failed: ' + e.message, '❌');
    }

    btnSaveVault.textContent = 'Save to OS Keychain';
    btnSaveVault.disabled = false;
});

// ---------- Toolbar ----------

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
        showToast('Split view disabled', '🔲');
    } else {
        showToast('Split view active (drag center divider)', '◫');
    }
    syncActiveStates();
    updateNavState();
};

document.getElementById('btn-back').onclick = () => { const wv = getActiveWebview(); if (wv) { try { wv.goBack(); } catch (e) {} } };
document.getElementById('btn-forward').onclick = () => { const wv = getActiveWebview(); if (wv) { try { wv.goForward(); } catch (e) {} } };
document.getElementById('btn-reload').onclick = () => { const wv = getActiveWebview(); if (wv) { try { wv.reload(); } catch (e) {} } };

// ---------- Settings Modal ----------

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
        showToast('Settings saved — reloading…', '✅');
        // Reload the UI in place: the app stays open and sessions persist
        setTimeout(() => window.location.reload(), 900);
    } catch (err) {
        showToast('Invalid JSON syntax!', '❌');
    }
};
