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

// ---------- Theme & UI settings ----------
let uiSettings = { theme: 'dark', accent: '#0078D7', hibernateMinutes: 20 };

function parseHex(hex) {
    let h = String(hex || '').replace('#', '');
    if (h.length === 3) h = h.split('').map(c => c + c).join('');
    if (!/^[0-9a-fA-F]{6}$/.test(h)) return [0, 120, 215];
    const n = parseInt(h, 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
function toHex(r, g, b) {
    return '#' + [r, g, b].map(v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, '0')).join('').toUpperCase();
}
function shade(hex, percent) {
    const [r, g, b] = parseHex(hex);
    const t = percent < 0 ? 0 : 255;
    const p = Math.abs(percent) / 100;
    return toHex(Math.round((t - r) * p + r), Math.round((t - g) * p + g), Math.round((t - b) * p + b));
}
function rgba(hex, a) {
    const [r, g, b] = parseHex(hex);
    return `rgba(${r}, ${g}, ${b}, ${a})`;
}

const systemTheme = window.matchMedia('(prefers-color-scheme: light)');

function applyTheme() {
    const effective = uiSettings.theme === 'system' ? (systemTheme.matches ? 'light' : 'dark') : uiSettings.theme;
    document.documentElement.dataset.theme = effective;

    const accent = uiSettings.accent;
    const s = document.documentElement.style;
    s.setProperty('--accent', accent);
    s.setProperty('--accent-hover', shade(accent, 16));
    s.setProperty('--accent-soft', rgba(accent, 0.18));
    s.setProperty('--accent-border', rgba(accent, 0.45));
    s.setProperty('--accent-bright', shade(accent, 24));
}

function persistUiSettings() {
    try { localStorage.setItem('webspace-ui', JSON.stringify(uiSettings)); } catch (e) {}
    if (window.api.saveSettings) window.api.saveSettings(uiSettings);
}

// Apply cached theme synchronously at boot (no flash), reconcile with disk after
try {
    const cached = JSON.parse(localStorage.getItem('webspace-ui') || 'null');
    if (cached) uiSettings = { ...uiSettings, ...cached };
} catch (e) {}
applyTheme();
systemTheme.addEventListener('change', () => { if (uiSettings.theme === 'system') applyTheme(); });

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
            // Hibernation check — silent; the tile dims as feedback
            const hibMs = (uiSettings.hibernateMinutes || 0) * 60000;
            if (obj.wv && !isVisible(obj.wv) && hibMs > 0 && (now - obj.lastAccessed > hibMs)) {
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
    if (window.api.getSettings) {
        try { uiSettings = { ...uiSettings, ...(await window.api.getSettings()) }; applyTheme(); } catch (e) {}
    }
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
        },
        {
            name: 'Toggle light / dark theme',
            icon: '🌓',
            action: () => {
                const cur = document.documentElement.dataset.theme;
                uiSettings.theme = cur === 'light' ? 'dark' : 'light';
                applyTheme();
                persistUiSettings();
                showToast(`Theme: ${uiSettings.theme}`, '🎨');
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

// ---------- Shared icon set (mini buttons) ----------

const ICONS = {
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5"/><path d="M5 12l7-7 7 7"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14"/><path d="M19 12l-7 7-7-7"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M6.5 6.5l11 11"/><path d="M17.5 6.5l-11 11"/></svg>',
    eye: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
    trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>'
};

function escAttr(s) {
    return String(s == null ? '' : s)
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

// ---------- Vault Modal (list + add/edit) ----------

const btnVault = document.getElementById('btn-vault');
const vaultModal = document.getElementById('vault-modal');
const vaultListEl = document.getElementById('vault-list');

function refreshVaultList() {
    return window.api.listCredentials().then(list => {
        list = list || [];
        if (!list.length) {
            vaultListEl.innerHTML = '<div class="empty-note">No credentials stored yet</div>';
            return;
        }
        vaultListEl.innerHTML = list.map(c => `
            <div class="vault-row" data-app="${escAttr(c.appName)}">
                <div class="vault-meta">
                    <div class="vault-app">${escAttr(c.appName)}</div>
                    <div class="vault-user">${escAttr(c.username)}</div>
                </div>
                <span class="vault-pw" hidden></span>
                <div class="vault-actions">
                    <button class="mini-btn" data-act="reveal" title="Reveal password">${ICONS.eye}</button>
                    <button class="mini-btn" data-act="copy-user" title="Copy username">${ICONS.copy}</button>
                    <button class="mini-btn" data-act="copy-pass" title="Copy password">${ICONS.copy}</button>
                    <button class="mini-btn danger" data-act="delete" title="Delete credentials">${ICONS.trash}</button>
                </div>
            </div>`).join('');
    }).catch(() => {
        vaultListEl.innerHTML = '<div class="empty-note">Could not read vault</div>';
    });
}

function resetVaultForm() {
    document.getElementById('vault-appname').value = activeApp ? activeApp.app.name : '';
    document.getElementById('vault-username').value = '';
    document.getElementById('vault-password').value = '';
    document.getElementById('vault-form-title').textContent = 'Add credential';
}

btnVault.addEventListener('click', () => {
    vaultModal.classList.add('show');
    resetVaultForm();
    refreshVaultList();
    document.getElementById('vault-username').focus();
});

vaultListEl.addEventListener('click', async (e) => {
    const meta = e.target.closest('.vault-meta');
    const btn = e.target.closest('button');

    // Click the metadata → load entry into the form for updating
    if (meta && !btn) {
        const row = meta.closest('.vault-row');
        document.getElementById('vault-appname').value = row.dataset.app;
        document.getElementById('vault-username').value = meta.querySelector('.vault-user').textContent;
        document.getElementById('vault-password').value = '';
        document.getElementById('vault-form-title').textContent = 'Update credential';
        document.getElementById('vault-password').focus();
        return;
    }
    if (!btn) return;

    const row = btn.closest('.vault-row');
    const appName = row.dataset.app;
    const act = btn.dataset.act;

    if (act === 'delete') {
        showToast(`Delete stored credentials for "${appName}"?`, '🗑️', {
            label: 'Delete',
            onClick: async () => {
                const res = await window.api.deleteCredential(appName);
                if (res && res.success) {
                    showToast(`Deleted credentials for ${appName}`, '🗑️');
                    refreshVaultList();
                } else {
                    showToast('Delete failed: ' + ((res && res.error) || 'unknown error'), '❌');
                }
            }
        });
        return;
    }

    if (act === 'copy-user') {
        const username = row.querySelector('.vault-user').textContent;
        await window.api.writeClipboard(username);
        showToast(`Username copied for ${appName}`, '📋');
        return;
    }

    const cred = await window.api.getCredential(appName);
    if (!cred || !cred.password) {
        showToast(`Could not decrypt password for ${appName}`, '❌');
        return;
    }

    if (act === 'copy-pass') {
        await window.api.writeClipboard(cred.password);
        showToast(`Password copied for ${appName} — clipboard clears on next copy`, '📋');
    } else if (act === 'reveal') {
        const pwEl = row.querySelector('.vault-pw');
        const metaEl = row.querySelector('.vault-meta');
        pwEl.textContent = cred.password;
        pwEl.hidden = false;
        metaEl.hidden = true;
        setTimeout(() => { pwEl.hidden = true; metaEl.hidden = false; }, 5000);
    }
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
            document.getElementById('vault-password').value = '';
            document.getElementById('vault-form-title').textContent = 'Add credential';
            refreshVaultList();
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

// ---------- Settings Manager (Appearance / Profiles & Apps / Advanced) ----------

const settingsModal = document.getElementById('settings-modal');
const profilesEditor = document.getElementById('profiles-editor');
const configEditorEl = document.getElementById('config-editor');
let settingsTab = 'appearance';

function appItemMarkup(app) {
    app = app || {};
    const letter = ((app.name || '?').charAt(0) || '?').toUpperCase();
    const css = app.customCSS || '';
    return `<div class="app-item ${css ? 'css-open' : ''}">
        <div class="app-row">
            <span class="app-tile"><span class="tile-letter">${escAttr(letter)}</span></span>
            <input type="text" class="input sm app-name-in" placeholder="Name" value="${escAttr(app.name)}">
            <input type="text" class="input sm app-url-in" placeholder="https://example.com" value="${escAttr(app.url)}">
            <button class="mini-btn app-up" title="Move up">${ICONS.up}</button>
            <button class="mini-btn app-down" title="Move down">${ICONS.down}</button>
            <button class="mini-btn app-css ${css ? 'css-on' : ''}" title="Custom CSS">{ }</button>
            <button class="mini-btn danger app-del" title="Remove app">${ICONS.close}</button>
        </div>
        <textarea class="app-css-editor" placeholder="/* Custom CSS for this app */">${escAttr(css)}</textarea>
    </div>`;
}

function profileCardMarkup(name, apps) {
    return `<div class="profile-card">
        <div class="profile-head">
            <input type="text" class="input sm profile-name" placeholder="Profile name" value="${escAttr(name)}">
            <button class="mini-btn prof-up" title="Move profile up">${ICONS.up}</button>
            <button class="mini-btn prof-down" title="Move profile down">${ICONS.down}</button>
            <button class="mini-btn danger prof-del" title="Remove profile">${ICONS.close}</button>
        </div>
        <div class="app-items">
            ${(Array.isArray(apps) ? apps : []).map(appItemMarkup).join('')}
            <button class="ghost-btn app-add" style="margin: 8px 10px 10px;">+ Add app</button>
        </div>
    </div>`;
}

function renderProfilesEditor(config) {
    profilesEditor.innerHTML = Object.entries(config)
        .map(([name, apps]) => profileCardMarkup(name, apps)).join('');
}

function configFromDom() {
    const cfg = {};
    profilesEditor.querySelectorAll('.profile-card').forEach(card => {
        const pname = card.querySelector('.profile-name').value.trim() || 'Untitled';
        const apps = [];
        card.querySelectorAll('.app-item').forEach(item => {
            const app = {
                name: item.querySelector('.app-name-in').value.trim(),
                url: item.querySelector('.app-url-in').value.trim()
            };
            const css = item.querySelector('.app-css-editor').value.trim();
            if (css) app.customCSS = css;
            apps.push(app);
        });
        cfg[pname] = apps;
    });
    return cfg;
}

function validateConfig(cfg) {
    const profiles = Object.entries(cfg);
    if (profiles.length === 0) return 'Add at least one profile';
    for (const [pname, apps] of profiles) {
        if (!Array.isArray(apps)) return `Profile "${pname}" must contain a list of apps`;
        for (const app of apps) {
            if (!app.name || !app.url) return `Every app in "${pname}" needs a name and URL`;
            if (!/^https?:\/\/\S+$/i.test(app.url)) return `URL for "${app.name}" must start with http(s)://`;
        }
    }
    return null;
}

// Delegated actions inside the profiles editor
profilesEditor.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (!btn) return;
    const item = btn.closest('.app-item');
    const card = btn.closest('.profile-card');

    if (btn.classList.contains('app-del')) {
        item.remove();
    } else if (btn.classList.contains('app-up') && item && item.previousElementSibling) {
        item.parentNode.insertBefore(item, item.previousElementSibling);
    } else if (btn.classList.contains('app-down') && item && item.nextElementSibling) {
        item.parentNode.insertBefore(item.nextElementSibling, item);
    } else if (btn.classList.contains('app-css') && item) {
        const open = item.classList.toggle('css-open');
        btn.classList.toggle('css-on', open);
        if (open) item.querySelector('.app-css-editor').focus();
    } else if (btn.classList.contains('app-add')) {
        btn.insertAdjacentHTML('beforebegin', appItemMarkup({ name: '', url: '' }));
        btn.previousElementSibling.querySelector('.app-name-in').focus();
    } else if (btn.classList.contains('prof-del')) {
        card.remove();
    } else if (btn.classList.contains('prof-up') && card && card.previousElementSibling) {
        profilesEditor.insertBefore(card, card.previousElementSibling);
    } else if (btn.classList.contains('prof-down') && card && card.nextElementSibling) {
        profilesEditor.insertBefore(card.nextElementSibling, card);
    }
});

document.getElementById('btn-add-profile').addEventListener('click', () => {
    profilesEditor.insertAdjacentHTML('beforeend', profileCardMarkup('', []));
    const cards = profilesEditor.querySelectorAll('.profile-card');
    cards[cards.length - 1].querySelector('.profile-name').focus();
});

// Tab switching (Advanced JSON syncs in both directions)
function switchSettingsTab(name) {
    if (name === settingsTab) return;
    if (settingsTab === 'advanced') {
        let parsed;
        try {
            parsed = JSON.parse(configEditorEl.value);
        } catch (e) {
            showToast('Fix the JSON syntax before leaving Advanced', '❌');
            return;
        }
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
            showToast('The JSON must be an object of profiles', '❌');
            return;
        }
        // Carry Advanced edits into the visual editor so nothing is lost
        renderProfilesEditor(parsed);
    }
    if (name === 'advanced') {
        configEditorEl.value = JSON.stringify(configFromDom(), null, 4);
    }
    settingsTab = name;
    document.querySelectorAll('.modal-head .tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
    ['appearance', 'profiles', 'advanced'].forEach(p => {
        document.getElementById('tab-' + p).hidden = (p !== name);
    });
}
document.querySelectorAll('.modal-head .tab').forEach(t => {
    t.addEventListener('click', () => switchSettingsTab(t.dataset.tab));
});

// Appearance controls
function updateHibLabel() {
    const v = parseInt(document.getElementById('hib-slider').value, 10);
    document.getElementById('hib-label').textContent = v === 0 ? 'Never' : `${v} min`;
}

function syncAppearanceControls() {
    document.querySelectorAll('#theme-seg .seg-btn').forEach(b =>
        b.classList.toggle('active', b.dataset.theme === uiSettings.theme));
    document.querySelectorAll('#accent-swatches .swatch').forEach(b =>
        b.classList.toggle('active', b.dataset.color.toLowerCase() === String(uiSettings.accent).toLowerCase()));
    document.getElementById('accent-custom').value = uiSettings.accent;
    document.getElementById('hib-slider').value = uiSettings.hibernateMinutes;
    updateHibLabel();
}

document.getElementById('theme-seg').addEventListener('click', (e) => {
    const b = e.target.closest('.seg-btn');
    if (!b) return;
    uiSettings.theme = b.dataset.theme;
    applyTheme();
    persistUiSettings();
    syncAppearanceControls();
});

document.getElementById('accent-swatches').addEventListener('click', (e) => {
    const b = e.target.closest('.swatch');
    if (!b) return;
    uiSettings.accent = b.dataset.color;
    applyTheme();
    persistUiSettings();
    syncAppearanceControls();
});

document.getElementById('accent-custom').addEventListener('input', (e) => {
    uiSettings.accent = e.target.value;
    applyTheme();
    syncAppearanceControls();
});
document.getElementById('accent-custom').addEventListener('change', persistUiSettings);

const hibSlider = document.getElementById('hib-slider');
hibSlider.addEventListener('input', () => {
    uiSettings.hibernateMinutes = parseInt(hibSlider.value, 10);
    updateHibLabel();
});
hibSlider.addEventListener('change', persistUiSettings);

// Open / cancel / save
document.getElementById('btn-settings').onclick = async () => {
    const cfg = await window.api.getConfig();
    renderProfilesEditor(cfg);
    syncAppearanceControls();
    settingsTab = 'profiles'; // sentinel: force panel refresh without re-syncing
    switchSettingsTab('appearance');
    settingsModal.classList.add('show');
};

document.getElementById('btn-cancel-settings').onclick = () => settingsModal.classList.remove('show');

document.getElementById('btn-save-settings').onclick = () => {
    let cfg;
    if (settingsTab === 'advanced') {
        try {
            cfg = JSON.parse(configEditorEl.value);
        } catch (err) {
            showToast('Invalid JSON syntax!', '❌');
            return;
        }
    } else {
        cfg = configFromDom();
        const cardCount = profilesEditor.querySelectorAll('.profile-card').length;
        if (Object.keys(cfg).length !== cardCount) {
            showToast('Profile names must be unique', '⚠️');
            return;
        }
    }

    const error = validateConfig(cfg);
    if (error) {
        showToast(error, '⚠️');
        return;
    }

    window.api.saveConfig(cfg);
    settingsModal.classList.remove('show');
    showToast('Settings saved — reloading…', '✅');
    // Reload the UI in place: the app stays open and sessions persist
    setTimeout(() => window.location.reload(), 900);
};
