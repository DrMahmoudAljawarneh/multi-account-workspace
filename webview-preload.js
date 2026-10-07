// The Ultimate Firefox Spoof Preload
(function() {
    'use strict';
    
    // 1. Spoof Firefox UA in DOM
    const FIREFOX_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0';
    try {
        Object.defineProperty(navigator, 'userAgent', { get: () => FIREFOX_UA, configurable: true });
        Object.defineProperty(navigator, 'appVersion', { get: () => '5.0 (Windows)', configurable: true });
        Object.defineProperty(navigator, 'vendor', { get: () => '', configurable: true });
    } catch (e) {}

    // 2. Destroy Chromium-specific APIs (Google checks these to verify it's NOT Firefox)
    try {
        delete window.chrome;
        Object.defineProperty(window, 'chrome', { get: () => undefined, configurable: true });
    } catch (e) {}

    // 3. Destroy User Agent Client Hints (Firefox doesn't have this, Chromium does)
    try {
        delete navigator.userAgentData;
        Object.defineProperty(navigator, 'userAgentData', { get: () => undefined, configurable: true });
    } catch (e) {}

    // 4. Strip webdriver & electron artifacts
    try {
        Object.defineProperty(navigator, 'webdriver', { get: () => false, configurable: true });
        delete window.electron;
        delete window.process;
    } catch (e) {}

    // 5. Emulate standard Firefox plugins array
    try {
        const dummyPlugins = [];
        Object.defineProperty(navigator, 'plugins', { get: () => dummyPlugins, configurable: true });
    } catch (e) {}
})();
