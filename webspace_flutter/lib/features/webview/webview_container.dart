import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import '../../core/providers.dart';
import '../../core/host_match.dart';
import '../../core/session_store.dart';
import '../../core/vault_service.dart';
import '../../core/viewport.dart';

class WebviewContainer extends ConsumerStatefulWidget {
  final String profileId;
  final String initialUrl;
  final String profileName;
  final String? customCSS;
  final bool isBrowser;
  final String pane; // 'main' or 'split' — registry key for toolbar control

  const WebviewContainer({
    super.key,
    required this.profileId,
    required this.initialUrl,
    required this.profileName,
    this.customCSS,
    this.isBrowser = false,
    this.pane = 'main',
  });

  @override
  ConsumerState<WebviewContainer> createState() => _WebviewContainerState();
}

class _WebviewContainerState extends ConsumerState<WebviewContainer> {
  late WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  bool _isHibernating = false;
  bool _hasBeenInitialized = false;
  bool _hasLoadError = false;
  String _loadErrorMessage = '';
  Timer? _hibernationTimer;

  /// Current page URL, updated on navigation — the anchor for host checks
  /// (auto-fill / save prompts) and permission dialog captions.
  String _lastUrl = '';

  String get _registryKey => '${widget.pane}_${widget.profileId}';

  /// True when this profile is the active app **in this container's own
  /// pane** (by stable id). The main pane must not wake for `activeId2`:
  /// that would spin up a duplicate webview — and native GTK overlay — for
  /// the split pane's app, painted over the main pane (RenderIndexedStack
  /// never overrides `paintsChild`, so webview_all_linux can't tell a
  /// non-selected IndexedStack child is hidden).
  bool get _isActive {
    if (widget.pane == 'split') {
      return ref.read(activeProfileId2Provider) == widget.profileId;
    }
    return ref.read(activeProfileIdProvider) == widget.profileId;
  }

  @override
  void initState() {
    super.initState();
    if (_isActive) {
      _hasBeenInitialized = true;
      _initializeWebview();
    }
  }

  @override
  void dispose() {
    _hibernationTimer?.cancel();
    final registry = ref.read(webviewControllersProvider.notifier);
    final key = _registryKey;
    // Provider state must not be modified synchronously during dispose
    Future.microtask(() => registry.unregister(key));
    _urlController.dispose();
    super.dispose();
  }

  void _initializeWebview() {
    _controller = WebViewController(onPermissionRequest: _handlePermissionRequest)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0")
      ..setOnConsoleMessage((message) {
        debugPrint('WebView Console: ${message.message}');
      })
      // Surface JS alert()/confirm()/prompt() in Flutter dialogs — without
      // these handlers the Linux plugin silently auto-confirms every dialog,
      // so pages that talk to the user via alert() just appear broken.
      ..setOnJavaScriptAlertDialog((request) async {
        await _showJsAlert(request.message, request.url);
      })
      ..setOnJavaScriptConfirmDialog((request) async =>
          _showJsConfirm(request.message, request.url))
      ..setOnJavaScriptTextInputDialog((request) async =>
          _showJsPrompt(request.message, request.url, request.defaultText ?? ''))
      ..addJavaScriptChannel(
        'FlutterCommandPalette',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'openCommandPalette') {
            debugPrint('DEBUG: Ctrl+K pressed (handled by WebView JavaScript bridge)');
            ref.read(isCommandPaletteOpenProvider.notifier).setOpen(true);
          } else if (message.message.startsWith('unread:')) {
            final count = int.tryParse(message.message.split(':')[1]) ?? 0;
            ref.read(unreadCountsProvider.notifier).updateCount(widget.profileId, count);
          } else if (message.message.startsWith('notification:')) {
            final title = message.message.substring(13);
            final notification = LocalNotification(
              title: title,
              subtitle: widget.profileName,
            );
            notification.show();
          } else if (message.message == 'openFind') {
            ref.read(isFindOpenProvider.notifier).setOpen(true);
          } else if (message.message == 'zoomIn') {
            _adjustZoom(0.1);
          } else if (message.message == 'zoomOut') {
            _adjustZoom(-0.1);
          } else if (message.message == 'zoomWheelIn') {
            _adjustZoom(0.1);
          } else if (message.message == 'zoomWheelOut') {
            _adjustZoom(-0.1);
          } else if (message.message == 'zoomReset') {
            _adjustZoom(null);
          } else if (message.message == 'toggleMute') {
            ViewportCommands.toggleMute(ref, widget.profileId);
          } else if (message.message == 'toggleSidebar') {
            ref.read(isSidebarCollapsedProvider.notifier).toggle();
          } else if (message.message == 'toggleSplit') {
            _toggleSplit();
          } else if (message.message.startsWith('goto:')) {
            final idx = int.tryParse(message.message.substring(5)) ?? -1;
            final profiles = ref.read(profilesProvider);
            if (idx >= 0 && idx < profiles.length) {
              // Keys pressed inside a pane switch apps in THAT pane, so
              // Ctrl+1..9 works per-pane while split view is active.
              if (widget.pane == 'split') {
                ref
                    .read(activeProfileId2Provider.notifier)
                    .select(profiles[idx].id);
              } else {
                ref
                    .read(activeProfileIdProvider.notifier)
                    .select(profiles[idx].id);
              }
            }
          } else if (message.message == 'autofill:need') {
            _tryAutofill();
          } else if (message.message.startsWith('creds:')) {
            final parts = message.message.split(':');
            if (parts.length == 3) {
              final user = _decodeBase64(parts[1]);
              final pass = _decodeBase64(parts[2]);
              if (user != null && pass != null) {
                _handleCredsCandidate(user, pass);
              }
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100 && mounted) {
              setState(() => _isLoading = false);
            }
          },
          onPageStarted: (String url) {
            _lastUrl = url;
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasLoadError = false;
                _loadErrorMessage = '';
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Only surface main-frame failures (subresource 404s are normal)
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _hasLoadError = true;
                _loadErrorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            // Let all links open natively inside the WebSpace app!
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasLoadError = false;
              });
              if (widget.isBrowser) {
                _urlController.text = url;
              }
            }

            // Remember where this app ended up so a restart restores it
            SessionStore.setUrl(widget.profileId, url);
            
            // Inject Custom CSS
            final customCss = widget.customCSS;
            if (customCss != null && customCss.isNotEmpty) {
              _controller.runJavaScript('''
                if (!window.customCssInjected) {
                  var style = document.createElement('style');
                  style.innerHTML = `$customCss`;
                  document.head.appendChild(style);
                  window.customCssInjected = true;
                }
              ''');
            }

            // Inject script to listen for shortcuts since WebViews swallow
            // hardware keys — mirrors the Flutter-side handlers. Ctrl+wheel
            // is captured here too so CSS zoom (not WebKit's native page
            // zoom) stays the single zoom system.
            _controller.runJavaScript('''
              if (!window.shortcutInjected) {
                var post = function(msg) {
                  if (typeof FlutterCommandPalette !== 'undefined') {
                    FlutterCommandPalette.postMessage(msg);
                  }
                };
                document.addEventListener('keydown', function(e) {
                  if (!e.ctrlKey) return;
                  var k = e.key;
                  if (k === 'k') { e.preventDefault(); post('openCommandPalette'); }
                  else if (k === 'f') { e.preventDefault(); post('openFind'); }
                  else if (k === '=' || k === '+') { e.preventDefault(); post('zoomIn'); }
                  else if (k === '-') { e.preventDefault(); post('zoomOut'); }
                  else if (k === '0') { e.preventDefault(); post('zoomReset'); }
                  else if (k === 'b' || k === 'B') { e.preventDefault(); post('toggleSidebar'); }
                  else if (k === 'S' || k === 's') { e.preventDefault(); post('toggleSplit'); }
                  else if ((k === 'M' || k === 'm') && e.shiftKey) { e.preventDefault(); post('toggleMute'); }
                  else if (k >= '1' && k <= '9') { e.preventDefault(); post('goto:' + (parseInt(k, 10) - 1)); }
                });
                window.addEventListener('wheel', function(e) {
                  if (!e.ctrlKey) return;
                  e.preventDefault();
                  post(e.deltaY < 0 ? 'zoomWheelIn' : 'zoomWheelOut');
                }, { passive: false });
                window.shortcutInjected = true;
              }
            ''');

            // Inject script to scrape unread notification badges (Franz style)
            _controller.runJavaScript('''
              if (!window.unreadInjected) {
                function checkUnread() {
                  var match = document.title.match(/\\((\\d+)\\)/);
                  var count = match ? parseInt(match[1], 10) : 0;
                  if (typeof FlutterCommandPalette !== 'undefined') {
                    FlutterCommandPalette.postMessage('unread:' + count);
                  }
                }
                checkUnread();
                new MutationObserver(checkUnread).observe(document.querySelector('title') || document.head, { subtree: true, characterData: true, childList: true });
                window.unreadInjected = true;
              }
            ''');

            // Inject script to intercept HTML5 Notifications
            _controller.runJavaScript('''
              if (!window.notificationsInjected) {
                const OriginalNotification = window.Notification;
                if (OriginalNotification) {
                  window.Notification = function(title, options) {
                    if (typeof FlutterCommandPalette !== 'undefined') {
                      FlutterCommandPalette.postMessage('notification:' + title);
                    }
                    return new OriginalNotification(title, options);
                  };
                  window.Notification.requestPermission = OriginalNotification.requestPermission;
                  window.Notification.permission = OriginalNotification.permission;
                }
                window.notificationsInjected = true;
              }
            ''');

            // Restore this app's persisted zoom / mute on every load
            ViewportCommands.reapplyOnLoad(ref, widget.profileId, (js) =>
                _controller.runJavaScript(js));

            // Look for a login form and ask Dart to auto-fill it silently —
            // but only when this page is on the profile's own domain(s), so
            // credentials never leak into an unrelated site's form.
            if (_isTrustedHostFor(url)) {
              _controller.runJavaScript('''
                setTimeout(function() {
                  if (document.querySelector('input[type=password]') &&
                      typeof FlutterCommandPalette !== 'undefined') {
                    FlutterCommandPalette.postMessage('autofill:need');
                  }
                }, 600);
              ''');
            }

            // Watch real form submissions so Dart can offer to save the
            // password (browsers-style "Save password?" snackbar).
            _controller.runJavaScript('''
              if (!window.credsHookInjected) {
                document.addEventListener('submit', function(e) {
                  var form = e.target;
                  if (!form || form.tagName !== 'FORM') return;
                  var pw = form.querySelector('input[type=password]');
                  if (!pw || !pw.value) return;
                  var user = form.querySelector('input[type=email],input[type=text],input[name*="user" i],input[name*="login" i],input[name*="email" i]');
                  if (!user || !user.value) return;
                  try {
                    var enc = function(v) { return btoa(encodeURIComponent(v)); };
                    if (typeof FlutterCommandPalette !== 'undefined') {
                      FlutterCommandPalette.postMessage('creds:' + enc(user.value) + ':' + enc(pw.value));
                    }
                  } catch (err) {}
                }, true);
                window.credsHookInjected = true;
              }
            ''');
          },
        ),
      )
      // Restore the last visited URL for this app when we have one
      ..loadRequest(Uri.parse(
          SessionStore.load().urls[widget.profileId] ?? widget.initialUrl));

    // Expose the controller to the toolbar (back / forward / reload).
    // Deferred: initState runs during build, where provider writes throw.
    final registry = ref.read(webviewControllersProvider.notifier);
    final key = _registryKey;
    final controller = _controller;
    Future.microtask(() {
      if (mounted) {
        registry.register(key, controller);
      } else {
        registry.unregister(key);
      }
    });
  }

  /// Zoom step from the in-page shortcut bridge (delta null = reset).
  Future<void> _adjustZoom(double? delta) async {
    final next = await (delta == null
        ? ViewportCommands.zoomReset(ref, widget.profileId)
        : delta > 0
            ? ViewportCommands.zoomIn(ref, widget.profileId)
            : ViewportCommands.zoomOut(ref, widget.profileId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${(next * 100).round()}%'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  /// Ctrl+Shift+S — split toggle shared with the hardware shortcut handler.
  void _toggleSplit() {
    final enabled = ref.read(isSplitViewEnabledProvider);
    if (!enabled) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final current =
            indexForId(profiles, ref.read(activeProfileIdProvider));
        ref
            .read(activeProfileId2Provider.notifier)
            .select(profiles[(current + 1) % profiles.length].id);
      }
    }
    ref.read(isSplitViewEnabledProvider.notifier).toggle();
  }

  /// True when [url] is on the profile's own domain(s) — the gate for
  /// auto-fill and credential-save prompts.
  bool _isTrustedHostFor(String url) {
    final pageHost = Uri.tryParse(url)?.host ?? '';
    final homeHost = Uri.tryParse(widget.initialUrl)?.host ?? '';
    return hostsMatch(pageHost, homeHost);
  }

  bool get _onTrustedHost => _isTrustedHostFor(_lastUrl);

  /// Best label for dialog captions: the current page's host.
  String get _pageHost {
    final host = Uri.tryParse(_lastUrl)?.host ?? '';
    return host.isEmpty ? widget.profileName : host;
  }

  String _hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? _pageHost : host;
  }

  /// Fills a detected login form from the OS keyring — the profile's named
  /// entry first, then any vault entry whose domain matches the page host.
  /// Silent, once per page load, and only on the profile's own domains.
  Future<void> _tryAutofill() async {
    if (!_onTrustedHost) return;
    VaultCredential? cred;
    try {
      cred = await VaultService.findFor(
        host: Uri.tryParse(_lastUrl)?.host ?? '',
        appName: widget.profileName,
      );
    } catch (_) {
      return;
    }
    if (cred == null || !mounted) return;
    final user = jsonEncode(cred.username);
    final pass = jsonEncode(cred.password);
    try {
      await _controller.runJavaScript('''
        (() => {
          const pw = document.querySelector('input[type=password]:not([readonly]):not([disabled])');
          if (!pw) return;
          const form = pw.form || document;
          const user = form.querySelector('input[type=email],input[type=text],input[name*="user" i],input[name*="login" i],input[name*="email" i]');
          const set = (el, v) => {
            el.value = v;
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
          };
          if (user && !user.value) set(user, $user);
          if (!pw.value) set(pw, $pass);
        })();
      ''');
    } catch (_) {}
  }

  /// Decodes the bridge's `btoa(encodeURIComponent(v))` payload.
  String? _decodeBase64(String encoded) {
    try {
      return Uri.decodeFull(utf8.decode(base64Decode(encoded)));
    } catch (_) {
      return null;
    }
  }

  /// The page just submitted username+password: offer to store it in the
  /// vault (save when absent, update when changed, silence when identical).
  Future<void> _handleCredsCandidate(String user, String pass) async {
    if (!mounted || user.isEmpty || pass.isEmpty || !_onTrustedHost) return;
    VaultCredential? existing;
    try {
      existing = await VaultService.get(widget.profileName);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (existing != null &&
        existing.username == user &&
        existing.password == pass) {
      return;
    }
    final isUpdate = existing != null;
    final host = Uri.tryParse(_lastUrl)?.host ?? '';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(isUpdate
          ? 'Update saved password for ${widget.profileName}?'
          : 'Save password for ${widget.profileName}?'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: isUpdate ? 'Update' : 'Save',
        onPressed: () async {
          final ok = await VaultService.save(
            appName: widget.profileName,
            username: user,
            password: pass,
            domain: host,
          );
          messenger.showSnackBar(SnackBar(
            content: Text(ok
                ? 'Password saved for ${widget.profileName}'
                : 'Could not reach the system keyring'),
            duration: const Duration(seconds: 2),
          ));
        },
      ),
    ));
  }

  /// Camera / microphone requests — the Linux plugin denies them outright
  /// when no handler is installed, so ask the user first.
  Future<void> _handlePermissionRequest(WebViewPermissionRequest request) async {
    final wanted = request.types.map((t) => t.name).join(' and ');
    if (!mounted) {
      await request.deny();
      return;
    }
    final granted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow device access?'),
        content: Text(
            '"$_pageHost" wants to use your $wanted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Block'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (granted == true) {
      await request.grant();
    } else {
      await request.deny();
    }
  }

  /// JS alert() — surfaces the message instead of silently auto-confirming.
  Future<void> _showJsAlert(String message, String url) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_hostOf(url),
            style: const TextStyle(fontSize: 14)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// JS confirm() — returns the user's choice to the page.
  Future<bool> _showJsConfirm(String message, String url) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_hostOf(url),
                style: const TextStyle(fontSize: 14)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('OK'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// JS prompt() — prefilled text input; the plugin has no cancel path, so
  /// dismissing returns the default value (same as today's auto-confirm).
  Future<String> _showJsPrompt(
      String message, String url, String defaultValue) async {
    if (!mounted) return defaultValue;
    final ctrl = TextEditingController(text: defaultValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_hostOf(url), style: const TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(defaultValue),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result ?? defaultValue;
  }

  void _checkHibernation() {
    final isActive = _isActive;

    if (!isActive) {
      // Start hibernation timer if not active (timeout from settings; 0 = never)
      final minutes = ref.read(settingsProvider).hibernateMinutes;
      if (_hasBeenInitialized && minutes > 0) {
        _hibernationTimer ??= Timer(Duration(minutes: minutes), () {
          if (mounted) {
            ref
                .read(webviewControllersProvider.notifier)
                .unregister(_registryKey);
            setState(() {
              _isHibernating = true;
            });
          }
        });
      }
    } else {
      // Cancel timer if active
      _hibernationTimer?.cancel();
      _hibernationTimer = null;

      if (!_hasBeenInitialized) {
        _hasBeenInitialized = true;
        _initializeWebview();
        return;
      }

      if (_isHibernating) {
        setState(() {
          _isHibernating = false;
          _isLoading = true;
        });
        _initializeWebview(); // Reload the webview
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to active selection changes in BOTH panes so split-pane switches
    // also wake / initialize the selected webview. (Which one *this* container
    // responds to is scoped by _isActive to its own pane.)
    ref.listen(activeProfileIdProvider, (previous, next) {
      _checkHibernation();
    });
    ref.listen(activeProfileId2Provider, (previous, next) {
      _checkHibernation();
    });

    final isCommandPaletteOpen = ref.watch(isCommandPaletteOpenProvider);
    // Which provider decides *this* pane's selection.
    final paneActiveId = widget.pane == 'split'
        ? ref.watch(activeProfileId2Provider)
        : ref.watch(activeProfileIdProvider);

    if (_hasLoadError) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(widget.profileName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _loadErrorMessage.isEmpty
                      ? 'Could not load this page'
                      : _loadErrorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _hasLoadError = false;
                    _isLoading = true;
                  });
                  _controller.reload();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isHibernating) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bedtime, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('${widget.profileName} is hibernating to save RAM', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (!_hasBeenInitialized) {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Starting ${widget.profileName}...', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Offstage(
          // Hide the native GTK overlay while the palette is open (Flutter
          // dialogs must paint above it) AND whenever this pane is not the
          // selected IndexedStack child: RenderIndexedStack doesn't override
          // paintsChild, so the plugin cannot detect the hidden child and
          // would otherwise keep the overlay painted over the selected app.
          offstage: isCommandPaletteOpen ||
              paneActiveId != widget.profileId,
          child: Column(
            children: [
              if (widget.isBrowser)
                Container(
                  color: Colors.black26,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 18),
                        onPressed: () => _controller.goBack(),
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: () => _controller.goForward(),
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => _controller.reload(),
                        splashRadius: 18,
                      ),
                      Expanded(
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                            onSubmitted: (value) {
                              var url = value;
                              if (!url.startsWith('http')) {
                                url = 'https://$url';
                              }
                              _controller.loadRequest(Uri.parse(url));
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: WebViewWidget(controller: _controller),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}
