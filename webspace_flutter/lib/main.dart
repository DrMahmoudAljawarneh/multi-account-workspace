import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
// Native tray API (the 0.5.x `legacy.dart` wrappers are deprecated).
// Imported with a prefix to keep nativeapi's `Image` from clashing with
// Flutter's Image widget.
import 'package:tray_manager/tray_manager.dart' as nativeapi;
import 'package:local_notifier/local_notifier.dart';
import 'core/app_settings.dart';
import 'core/providers.dart';
import 'core/overlay_gate.dart';
import 'core/config_manager.dart';
import 'core/session_store.dart';
import 'core/viewport.dart';
import 'features/find/find_bar.dart';
import 'features/palette/command_palette.dart';
import 'features/panes/pane_header.dart';
import 'features/sidebar/sidebar_panel.dart';
import 'features/titlebar/app_titlebar.dart';
import 'features/toolbar/app_toolbar.dart';
import 'features/webview/webview_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load profiles from config.json + shared UI settings
  initialProfiles = await ConfigManager.loadProfiles();
  initialSettings = SettingsStore.load();

  // Restore last session (active app, split, sidebar, URLs, zoom, mute),
  // healing any ids that no longer exist in the profile list.
  initialSession =
      SessionStore.load().validate(initialProfiles.map((p) => p.id).toSet());
  // Persist the healed state right away: without this, activeAppId only
  // reached disk if the user changed something, so a no-interaction run
  // left the file without a selection to restore next time.
  await SessionStore.save(initialSession);

  // Initialize the tray icon through tray_manager's native API
  await _initTray();
  
  // Initialize local notifier
  await localNotifier.setup(
    appName: 'WebSpace',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  
  // Initialize window manager for frameless title bar
  await windowManager.ensureInitialized();

  // Restore the previous window placement when we remember one; otherwise
  // fall back to the default 1200x800, centered as before.
  final savedBounds = initialSession.windowBounds;
  WindowOptions windowOptions = WindowOptions(
    size: savedBounds != null
        ? Size(savedBounds['width']!, savedBounds['height']!)
        : const Size(1200, 800),
    center: savedBounds == null,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'WebSpace',
    titleBarStyle: TitleBarStyle.hidden, // Hides native title bar
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (savedBounds != null) {
      try {
        await windowManager.setBounds(Rect.fromLTWH(
          savedBounds['x']!,
          savedBounds['y']!,
          savedBounds['width']!,
          savedBounds['height']!,
        ));
      } catch (_) {}
    }
    await windowManager.setTitle('WebSpace');
    await windowManager.show();
    if (initialSession.windowMaximized) {
      try {
        await windowManager.maximize();
      } catch (_) {}
    }
    await windowManager.focus();
    try {
      // window_manager resolves this against
      // <exe_dir>/data/flutter_assets, which is correct both for the
      // installed bundle (/opt/webspace) and the dist/ dev bundle.
      // (Passing an absolute path here would break it: the plugin joins
      // the two, producing a nonexistent path.)
      final iconFile = File(
          '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/icon.png');
      debugPrint('Window icon asset exists: ${await iconFile.exists()}');
      await windowManager.setIcon('assets/icon.png');
    } catch (e) {
      debugPrint('Error setting icon: $e');
    }
  });
  await windowManager.setPreventClose(true);

  runApp(
    const ProviderScope(
      child: WebSpaceApp(),
    ),
  );
}

/// Builds a [ThemeData] from the persisted accent, matching the Electron
/// palette (dark #1E1E1E / light #ECEEF1 surfaces).
ThemeData _buildTheme(Brightness brightness, Color accent) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFECEEF1),
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: isDark ? const Color(0xFF252526) : const Color(0xFFF7F8FA),
    ),
  );
}

Color _accentFromHex(String hex) {
  try {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  } catch (_) {
    return const Color(0xFF0078D7);
  }
}

// Native handles retained for the lifetime of the process. The native
// binding attaches a finalizer that destroys the tray icon (and
// unregisters it from the StatusNotifier watcher) as soon as its Dart
// object is garbage-collected — keeping them in locals inside _initTray
// killed the tray silently right after startup.
final List<Object?> _trayHandles = [];

Future<void> _initTray() async {
  try {
    final tray = nativeapi.TrayIcon.create();
    if (tray == null) return;
    final icon = nativeapi.ImageAsset.fromAsset('assets/icon.png') ??
        nativeapi.Image.fromFile('assets/icon.png');
    _trayHandles.addAll([tray, icon]);
    tray
      ..icon = icon
      ..isIconTemplate = false
      ..iconSize = const Size.square(18)
      ..setTooltip('WebSpace')
      ..setVisible(true);

    final menu = nativeapi.Menu.create();
    final showItem = nativeapi.MenuItem.createWithLabelAndType(
        'Show WebSpace', nativeapi.MenuItemType.normal);
    final exitItem = nativeapi.MenuItem.createWithLabelAndType(
        'Exit', nativeapi.MenuItemType.normal);
    final separator = nativeapi.MenuItem.createWithLabelAndType(
        '', nativeapi.MenuItemType.separator);
    menu?.addItem(showItem);
    menu?.addItem(separator);
    menu?.addItem(exitItem);
    tray.setContextMenu(menu);
    // Retain everything the native side owns through these handles.
    _trayHandles.addAll([menu, showItem, separator, exitItem]);

    // Left-click on the tray icon → show the window
    tray.addListener((event) {
      if (event is nativeapi.TrayIconClickedEvent) {
        windowManager.show();
        windowManager.focus();
      }
    });

    // Context-menu item clicks (per-item listeners, like the legacy wiring)
    showItem?.addListener((event) {
      if (event is nativeapi.MenuItemClickedEvent) {
        windowManager.show();
        windowManager.focus();
      }
    });
    exitItem?.addListener((event) {
      if (event is nativeapi.MenuItemClickedEvent) {
        windowManager.destroy();
      }
    });
  } catch (e) {
    debugPrint('Tray unavailable: $e');
  }
}

class WebSpaceApp extends ConsumerWidget {
  const WebSpaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accent = _accentFromHex(settings.accent);

    return MaterialApp(
      title: 'WebSpace',
      debugShowCheckedModeBanner: false,
      themeMode: switch (settings.theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      theme: _buildTheme(Brightness.light, accent),
      darkTheme: _buildTheme(Brightness.dark, accent),
      home: const WorkspaceScreen(),
    );
  }
}

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    _boundsTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    windowManager.removeListener(this);
    super.dispose();
  }
  
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  Timer? _boundsTimer;

  // Window placement persistence: written shortly after the user stops
  // dragging/resizing (debounced), immediately on maximize changes.
  @override
  void onWindowMoved() => _queueBoundsSave();

  @override
  void onWindowResized() => _queueBoundsSave();

  @override
  void onWindowMaximize() => _persistBounds(maximized: true);

  @override
  void onWindowUnmaximize() => _persistBounds(maximized: false);

  void _queueBoundsSave() {
    _boundsTimer?.cancel();
    _boundsTimer =
        Timer(const Duration(milliseconds: 800), () => _persistBounds());
  }

  Future<void> _persistBounds({bool? maximized}) async {
    try {
      final rect = await windowManager.getBounds();
      if (rect.width < 200 || rect.height < 200) return;
      final isMax = maximized ?? await windowManager.isMaximized();
      await SessionStore.patch({
        'window': {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
        },
        'windowMaximized': isMax,
      });
    } catch (_) {}
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyK) {
        debugPrint('DEBUG: Ctrl+K pressed (handled by Flutter main window)');
        ref.read(isCommandPaletteOpenProvider.notifier).setOpen(true);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
        ref.read(isSidebarCollapsedProvider.notifier).toggle();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        final splitEnabled = ref.read(isSplitViewEnabledProvider);
        if (!splitEnabled) {
          final profiles = ref.read(profilesProvider);
          if (profiles.isNotEmpty) {
            final current =
                indexForId(profiles, ref.read(activeProfileIdProvider));
            ref.read(activeProfileId2Provider.notifier).select(
                profiles[(current + 1) % profiles.length].id);
          }
        }
        ref.read(isSplitViewEnabledProvider.notifier).toggle();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyF &&
          !HardwareKeyboard.instance.isShiftPressed) {
        ref.read(isFindOpenProvider.notifier).toggle();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyM &&
          HardwareKeyboard.instance.isShiftPressed) {
        final id = focusedActiveId(ref);
        if (id != null) {
          ViewportCommands.toggleMute(ref, id).then((_) {
            if (!mounted) return;
            final muted =
                ref.read(mutedAppsProvider.notifier).isMuted(id);
            showTransientNotice(
                context, ref, muted ? 'Audio muted' : 'Audio unmuted');
          });
        }
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.equal ||
          event.logicalKey == LogicalKeyboardKey.minus ||
          event.logicalKey == LogicalKeyboardKey.digit0) {
        final id = focusedActiveId(ref);
        if (id != null) {
          final key = event.logicalKey;
          final Future<double> result;
          if (key == LogicalKeyboardKey.minus) {
            result = ViewportCommands.zoomOut(ref, id);
          } else if (key == LogicalKeyboardKey.digit0) {
            result = ViewportCommands.zoomReset(ref, id);
          } else {
            result = ViewportCommands.zoomIn(ref, id);
          }
          result.then((next) {
            if (!mounted) return;
            showTransientNotice(context, ref, '${(next * 100).round()}%');
          });
        }
        return true;
      } else if (event.logicalKey.keyId >= LogicalKeyboardKey.digit1.keyId && 
                 event.logicalKey.keyId <= LogicalKeyboardKey.digit9.keyId) {
        int index = event.logicalKey.keyId - LogicalKeyboardKey.digit1.keyId;
        final profiles = ref.read(profilesProvider);
        if (index < profiles.length) {
          selectIntoFocusedPane(ref, profiles[index].id);
        }
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isCommandPaletteOpenProvider, (previous, next) {
      debugPrint('DEBUG: isCommandPaletteOpenProvider changed: prev=$previous, next=$next');
      if (next && !(previous ?? false)) {
        showCommandPalette(context, ref);
      }
    });

    // Session persistence — mirror selection/UI state to session.flutter.json
    ref.listen(activeProfileIdProvider, (_, next) =>
        SessionStore.patch({'activeAppId': next}));
    ref.listen(activeProfileId2Provider, (_, next) =>
        SessionStore.patch({'activeAppId2': next}));
    ref.listen(isSplitViewEnabledProvider, (_, next) =>
        SessionStore.patch({'splitView': next}));
    ref.listen(isSidebarCollapsedProvider, (_, next) =>
        SessionStore.patch({'sidebarCollapsed': next}));
    ref.listen(isSidebarExpandedProvider, (_, next) =>
        SessionStore.patch({'sidebarExpanded': next}));
    ref.listen(focusedPaneProvider, (_, next) =>
        SessionStore.patch({'focusedPane': next}));

    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final activeId2 = ref.watch(activeProfileId2Provider);
    final selectedIndex = indexForId(profiles, activeId);
    final isSidebarCollapsed = ref.watch(isSidebarCollapsedProvider);
    final isSplitView = ref.watch(isSplitViewEnabledProvider);
    final splitPosition = ref.watch(splitDividerPositionProvider);
    final isFindOpen = ref.watch(isFindOpenProvider);
    final selectedIndex2 =
        activeId2 == null ? null : indexForId(profiles, activeId2);
    final scheme = Theme.of(context).colorScheme;

    // Mirror Electron's taskbar unread indicator in the window title
    ref.listen(unreadCountsProvider, (previous, next) {
      final total =
          next.values.fold<int>(0, (sum, n) => sum + (n > 0 ? n : 0));
      windowManager.setTitle(total > 0 ? 'WebSpace ($total)' : 'WebSpace');
    });

    return Scaffold(
      body: Column(
          children: [
            const AppTitlebar(),
                        const AppToolbar(),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                  if (!isSidebarCollapsed)
                    const SidebarPanel(),
                                    if (!isSidebarCollapsed)
                    VerticalDivider(thickness: 1, width: 1, color: scheme.onSurface.withValues(alpha: 0.1)),
                  Expanded(
                    flex: isSplitView ? (splitPosition * 100).toInt() : 100,
                    child: Column(
                      children: [
                        if (isSplitView) const PaneHeader(pane: 'main'),
                        Expanded(
                          child: IndexedStack(
                            index: selectedIndex,
                            children: profiles.map((profile) {
                              return WebviewContainer(
                                key: ValueKey('main_${profile.id}'),
                                profileId: profile.id,
                                initialUrl: profile.initialUrl,
                                profileName: profile.name,
                                customCSS: profile.customCSS,
                                isBrowser: profile.isBrowser,
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSplitView && selectedIndex2 != null)
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final screenWidth = MediaQuery.of(context).size.width - (isSidebarCollapsed ? 0 : 72);
                          double newPos = splitPosition + (details.delta.dx / screenWidth);
                          ref.read(splitDividerPositionProvider.notifier).setPosition(newPos);
                        },
                        child: Container(width: 4, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  if (isSplitView && selectedIndex2 != null)
                    Expanded(
                      flex: ((1 - splitPosition) * 100).toInt(),
                      child: Column(
                        children: [
                          const PaneHeader(pane: 'split'),
                          Expanded(
                            child: IndexedStack(
                              index: selectedIndex2,
                              children: profiles.map((profile) {
                                return WebviewContainer(
                                  key: ValueKey('split_${profile.id}'),
                                  profileId: profile.id,
                                  initialUrl: profile.initialUrl,
                                  profileName: profile.name,
                                  customCSS: profile.customCSS,
                                  isBrowser: profile.isBrowser,
                                  pane: 'split',
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                  ),
                  if (isFindOpen)
                    const Positioned(
                      top: 10,
                      right: 16,
                      child: FindBar(),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
  }
}
