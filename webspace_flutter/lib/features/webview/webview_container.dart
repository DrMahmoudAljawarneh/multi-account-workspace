import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import '../../core/providers.dart';

class WebviewContainer extends ConsumerStatefulWidget {
  final String profileId;
  final String initialUrl;
  final String profileName;
  final int profileIndex;
  final String? customCSS;
  final bool isBrowser;
  final String pane; // 'main' or 'split' — registry key for toolbar control

  const WebviewContainer({
    super.key,
    required this.profileId,
    required this.initialUrl,
    required this.profileName,
    required this.profileIndex,
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

  String get _registryKey => '${widget.pane}_${widget.profileId}';

  @override
  void initState() {
    super.initState();
    final activeIndex = ref.read(activeProfileIndexProvider);
    final activeIndex2 = ref.read(activeProfileIndex2Provider);
    if (activeIndex == widget.profileIndex || activeIndex2 == widget.profileIndex) {
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) Gecko/20100101 Firefox/157.0")
      ..setOnConsoleMessage((message) {
        debugPrint('WebView Console: ${message.message}');
      })
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

            // Inject script to listen for Ctrl+K since WebViews swallow hardware keys
            _controller.runJavaScript('''
              if (!window.shortcutInjected) {
                document.addEventListener('keydown', function(e) {
                  if (e.ctrlKey && e.key === 'k') {
                    e.preventDefault();
                    if (typeof FlutterCommandPalette !== 'undefined') {
                      FlutterCommandPalette.postMessage('openCommandPalette');
                    }
                  }
                });
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
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

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

  void _checkHibernation() {
    final activeIndex = ref.read(activeProfileIndexProvider);
    final activeIndex2 = ref.read(activeProfileIndex2Provider);
    final isActive = activeIndex == widget.profileIndex || activeIndex2 == widget.profileIndex;

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
    // Listen to active index changes in BOTH panes so split-pane switches
    // also wake / initialize the selected webview.
    ref.listen(activeProfileIndexProvider, (previous, next) {
      _checkHibernation();
    });
    ref.listen(activeProfileIndex2Provider, (previous, next) {
      _checkHibernation();
    });

    final isCommandPaletteOpen = ref.watch(isCommandPaletteOpenProvider);

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
          offstage: isCommandPaletteOpen,
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
