// The Ultimate Firefox Spoof Preload (Conditional)
(function() {
    'use strict';
    
    const isGoogle = window.location.hostname.includes('google.com') || window.location.hostname.includes('youtube.com');
    const FIREFOX_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0';
    const LINUX_CHROME_UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

    try {
        const isLogin = window.location.hostname.includes('login.microsoft') || window.location.hostname.includes('login.live.com');
        const IPAD_UA = 'Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';
        const UA = isLogin ? IPAD_UA : FIREFOX_UA;
        
        Object.defineProperty(navigator, 'userAgent', { get: () => UA, configurable: true });
        Object.defineProperty(navigator, 'appVersion', { get: () => isLogin ? '5.0 (iPad)' : '5.0 (Windows)', configurable: true });
        Object.defineProperty(navigator, 'platform', { get: () => isLogin ? 'iPad' : 'Win32', configurable: true });
        Object.defineProperty(navigator, 'vendor', { get: () => isLogin ? 'Apple Computer, Inc.' : '', configurable: true });
    } catch (e) {}

    // We MUST destroy Chromium-specific APIs so Google/Microsoft think it's a standard browser
    // and don't detect the Electron framework via Client Hints or window properties.
    try {
        delete window.chrome;
        Object.defineProperty(window, 'chrome', { get: () => undefined, configurable: true });
    } catch (e) {}

    try {
        delete navigator.userAgentData;
        Object.defineProperty(navigator, 'userAgentData', { get: () => undefined, configurable: true });
    } catch (e) {}

    // Always strip Electron/Webdriver artifacts
    try {
        Object.defineProperty(navigator, 'webdriver', { get: () => false, configurable: true });
        delete window.electron;
        delete window.process;
    } catch (e) {}

    // Instead of deleting the APIs, we strictly mock them to throw standard DOMExceptions.
    // When Microsoft's code tries to use WebAuthn, it expects either success or a specific exception.
    // Throwing 'NotSupportedError' forces Microsoft's internal error handler to instantly 
    // fall back and display the "Sign in with password" or "Sign in another way" buttons!
    try {
        const fakePKC = function() {};
        fakePKC.isUserVerifyingPlatformAuthenticatorAvailable = async () => false;
        fakePKC.isConditionalMediationAvailable = async () => false;
        Object.defineProperty(window, 'PublicKeyCredential', { get: () => fakePKC, configurable: true });
        if (typeof Window !== 'undefined') Window.prototype.PublicKeyCredential = fakePKC;
        
        const fakeCreds = {
            create: async () => { throw new DOMException('Not supported', 'NotSupportedError'); },
            get: async () => { throw new DOMException('Not supported', 'NotSupportedError'); },
            preventSilentAccess: async () => {}
        };
        Object.defineProperty(navigator, 'credentials', { get: () => fakeCreds, configurable: true });
        if (typeof Navigator !== 'undefined') Navigator.prototype.credentials = fakeCreds;
    } catch (e) {}

    if (isGoogle) {
        try {
            const dummyPlugins = [];
            Object.defineProperty(navigator, 'plugins', { get: () => dummyPlugins, configurable: true });
        } catch (e) {}
    }
})();
