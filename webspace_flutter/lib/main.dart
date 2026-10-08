import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/legacy.dart';
import 'package:local_notifier/local_notifier.dart';
import 'core/app_settings.dart';
import 'core/providers.dart';
import 'core/config_manager.dart';
import 'features/settings/settings_dialog.dart';
import 'features/toolbar/app_toolbar.dart';
import 'features/vault/vault_dialog.dart';
import 'features/webview/webview_container.dart';
import 'features/widgets/favicon_icon.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load profiles from config.json + shared UI settings
  initialProfiles = await ConfigManager.loadProfiles();
  initialSettings = SettingsStore.load();
  
  // Initialize tray manager
  await trayManager.setIcon(
    'assets/icon.png',
  );
  Menu menu = Menu(
    items: [
      MenuItem(
        key: 'show_window',
        label: 'Show WebSpace',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit',
      ),
    ],
  );
  await trayManager.setContextMenu(menu);
  
  // Initialize local notifier
  await localNotifier.setup(
    appName: 'WebSpace',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );
  
  // Initialize window manager for frameless title bar
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'WebSpace',
    titleBarStyle: TitleBarStyle.hidden, // Hides native title bar
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('WebSpace');
    await windowManager.show();
    await windowManager.focus();
    try {
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

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    trayManager.removeListener(this);
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

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
    }
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
          final current = ref.read(activeProfileIndexProvider);
          ref.read(activeProfileIndex2Provider.notifier).setIndex((current + 1) % profiles.length);
        }
        ref.read(isSplitViewEnabledProvider.notifier).toggle();
        return true;
      } else if (event.logicalKey.keyId >= LogicalKeyboardKey.digit1.keyId && 
                 event.logicalKey.keyId <= LogicalKeyboardKey.digit9.keyId) {
        int index = event.logicalKey.keyId - LogicalKeyboardKey.digit1.keyId;
        final profiles = ref.read(profilesProvider);
        if (index < profiles.length) {
          ref.read(activeProfileIndexProvider.notifier).setIndex(index);
        }
        return true;
      }
    }
    return false;
  }

  void _showCommandPalette() {
    debugPrint('DEBUG: _showCommandPalette() called');
    final appContext = context; // workspace context (dialog context dies on pop)
    String searchQuery = '';
    VoidCallback? pendingAction;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final profiles = ref.read(profilesProvider);
            final query = searchQuery.toLowerCase();

            final actions = <({
              String title,
              String subtitle,
              IconData icon,
              VoidCallback run,
            })>[
              (
                title: 'Settings…',
                subtitle: 'Appearance, profiles & apps, advanced JSON',
                icon: Icons.settings_outlined,
                run: () => showDialog(
                    context: appContext, builder: (_) => const SettingsDialog()),
              ),
              (
                title: 'Credential vault…',
                subtitle: 'Reveal, copy or update stored passwords',
                icon: Icons.key_outlined,
                run: () => showDialog(
                    context: appContext, builder: (_) => const VaultDialog()),
              ),
              (
                title: 'Toggle light / dark theme',
                subtitle: 'Switch appearance instantly',
                icon: Icons.brightness_6_outlined,
                run: () {
                  final s = ref.read(settingsProvider);
                  ref.read(settingsProvider.notifier).update(
                      s.copyWith(theme: s.theme == 'light' ? 'dark' : 'light'));
                },
              ),
            ];
            final filteredActions = actions
                .where((a) =>
                    a.title.toLowerCase().contains(query) ||
                    a.subtitle.toLowerCase().contains(query))
                .toList();
            final filteredProfiles = profiles
                .where((p) => p.name.toLowerCase().contains(query))
                .toList();

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                      width: 1),
                ),
                elevation: 20,
                shadowColor: Colors.black,
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: 'Search commands or profiles...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.black12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          searchQuery = value;
                        });
                      },
                      onSubmitted: (value) {
                        if (filteredActions.isNotEmpty) {
                          pendingAction = filteredActions.first.run;
                        } else if (filteredProfiles.isNotEmpty) {
                          final index = profiles.indexOf(filteredProfiles.first);
                          ref.read(activeProfileIndexProvider.notifier).setIndex(index);
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (filteredProfiles.isEmpty && filteredActions.isEmpty)
                      const Text('No profiles found', style: TextStyle(color: Colors.grey))
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount:
                              filteredActions.length + filteredProfiles.length,
                          itemBuilder: (context, index) {
                            if (index < filteredActions.length) {
                              final action = filteredActions[index];
                              return Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: Icon(action.icon),
                                  title: Text(action.title),
                                  subtitle: Text(action.subtitle,
                                      style: const TextStyle(fontSize: 12)),
                                  onTap: () {
                                    pendingAction = action.run;
                                    Navigator.of(context).pop();
                                  },
                                ),
                              );
                            }
                            final profile =
                                filteredProfiles[index - filteredActions.length];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: const Icon(Icons.web),
                                title: Text(profile.name),
                                subtitle: Text(profile.initialUrl),
                                onTap: () {
                                  final pIndex = profiles.indexOf(profile);
                                  ref.read(activeProfileIndexProvider.notifier).setIndex(pIndex);
                                  Navigator.of(context).pop();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                ),
              ),
            );
          }
        );
      },
    ).then((_) {
      debugPrint('DEBUG: Command Palette closed, resetting state to false');
      ref.read(isCommandPaletteOpenProvider.notifier).setOpen(false);
      final action = pendingAction;
      pendingAction = null;
      if (action != null) action();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isCommandPaletteOpenProvider, (previous, next) {
      debugPrint('DEBUG: isCommandPaletteOpenProvider changed: prev=$previous, next=$next');
      if (next && !(previous ?? false)) {
        debugPrint('DEBUG: triggering _showCommandPalette()');
        _showCommandPalette();
      }
    });

    final profiles = ref.watch(profilesProvider);
    final selectedIndex = ref.watch(activeProfileIndexProvider);
    final unreadCounts = ref.watch(unreadCountsProvider);
    final isSidebarCollapsed = ref.watch(isSidebarCollapsedProvider);
    final isSidebarExpanded = ref.watch(isSidebarExpandedProvider);
    final isSplitView = ref.watch(isSplitViewEnabledProvider);
    final splitPosition = ref.watch(splitDividerPositionProvider);
    final selectedIndex2 = ref.watch(activeProfileIndex2Provider);
    final scheme = Theme.of(context).colorScheme;
    final sidebarColor =
        Color.lerp(scheme.surface, Colors.black, 0.12) ?? scheme.surface;

    // Mirror Electron's taskbar unread indicator in the window title
    ref.listen(unreadCountsProvider, (previous, next) {
      final total =
          next.values.fold<int>(0, (sum, n) => sum + (n > 0 ? n : 0));
      windowManager.setTitle(total > 0 ? 'WebSpace ($total)' : 'WebSpace');
    });

    // Sidebar layout: group headers interleaved with profile entries
    final sidebarRows = <_SidebarRow>[];
    String? lastGroup;
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      if (!p.isBrowser && p.group != null && p.group != lastGroup) {
        sidebarRows.add(_SidebarRow.header(p.group!));
        lastGroup = p.group;
      }
      sidebarRows.add(_SidebarRow.item(i));
    }

    return Scaffold(
      body: Column(
          children: [
            // Custom Frameless Window Drag Area
            DragToMoveArea(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06), width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 16.0),
                      child: Text('WebSpace', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.minimize, size: 16),
                          onPressed: () => windowManager.minimize(),
                          splashRadius: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.crop_square, size: 16),
                          onPressed: () async {
                            if (await windowManager.isMaximized()) {
                              windowManager.unmaximize();
                            } else {
                              windowManager.maximize();
                            }
                          },
                          splashRadius: 16,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => windowManager.close(),
                          splashRadius: 16,
                          hoverColor: Colors.red.withValues(alpha: 0.8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const AppToolbar(),
            Expanded(
              child: Row(
                children: [
                  if (!isSidebarCollapsed)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSidebarExpanded ? 220 : 72,
                      decoration: BoxDecoration(
                        color: sidebarColor,
                        border: Border(right: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06), width: 1)),
                      ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: sidebarRows.length,
                            itemBuilder: (context, rowIdx) {
                              final row = sidebarRows[rowIdx];
                              if (row.isHeader) {
                                if (isSidebarExpanded) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(20, 18, 12, 4),
                                    child: Text(
                                      row.label!.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }
                                // Collapsed sidebar: subtle divider instead
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: Container(
                                      width: 24,
                                      height: 1,
                                      color: scheme.onSurface.withValues(alpha: 0.15),
                                    ),
                                  ),
                                );
                              }

                              final index = row.index;
                              final profile = profiles[index];
                              final isSelected = index == selectedIndex;
                              final unread = unreadCounts[profile.id] ?? 0;
                              return GestureDetector(
                                onTap: () => ref.read(activeProfileIndexProvider.notifier).setIndex(index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      // Active edge indicator
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 4,
                                        height: isSelected ? 32 : 12,
                                        decoration: BoxDecoration(
                                          color: isSelected 
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.transparent,
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(4),
                                            bottomRight: Radius.circular(4),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Franz/Discord style shape-shifting icon with badge
                                      Tooltip(
                                        message: profile.name,
                                        preferBelow: false,
                                        verticalOffset: 24,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: isSelected 
                                                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                                                    : scheme.onSurface.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                                                border: Border.all(
                                                  color: isSelected 
                                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5) 
                                                      : Colors.transparent,
                                                  width: 1,
                                                ),
                                                boxShadow: isSelected ? [
                                                  BoxShadow(
                                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                                    blurRadius: 8,
                                                    spreadRadius: 1,
                                                  )
                                                ] : null,
                                              ),
                                              alignment: Alignment.center,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                                                child: FaviconIcon(
                                                  url: profile.initialUrl,
                                                  fallbackLetter: profile.name.isEmpty
                                                      ? '?'
                                                      : profile.name.substring(0, 1),
                                                  size: 24,
                                                  letterColor: isSelected
                                                      ? Theme.of(context).colorScheme.primary
                                                      : scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            if (!isSidebarExpanded && unread > 0)
                                              Positioned(
                                                right: -4,
                                                bottom: -4,
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: sidebarColor, width: 2),
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Colors.black45,
                                                        blurRadius: 4,
                                                        offset: Offset(0, 2),
                                                      )
                                                    ],
                                                  ),
                                                  child: Text(
                                                    '$unread',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isSidebarExpanded) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            profile.name,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Theme.of(context).colorScheme.primary
                                                  : scheme.onSurfaceVariant,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                        if (unread > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              '$unread',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onPrimary,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Add Button
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.onSurface.withValues(alpha: 0.08),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.add, color: scheme.onSurfaceVariant),
                            onPressed: () {
                              ref.read(isCommandPaletteOpenProvider.notifier).setOpen(true);
                            },
                          ),
                        ),
                        // Toggle Expanded Button
                        IconButton(
                          icon: Icon(isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right),
                          color: scheme.onSurfaceVariant,
                          onPressed: () {
                            ref.read(isSidebarExpandedProvider.notifier).toggle();
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  if (!isSidebarCollapsed)
                    VerticalDivider(thickness: 1, width: 1, color: scheme.onSurface.withValues(alpha: 0.1)),
                  Expanded(
                    flex: isSplitView ? (splitPosition * 100).toInt() : 100,
                    child: IndexedStack(
                      index: selectedIndex,
                      children: profiles.asMap().entries.map((entry) {
                        final index = entry.key;
                        final profile = entry.value;
                        return WebviewContainer(
                          key: ValueKey('main_${profile.id}'),
                          profileId: profile.id,
                          initialUrl: profile.initialUrl,
                          profileName: profile.name,
                          profileIndex: index,
                          customCSS: profile.customCSS,
                          isBrowser: profile.isBrowser,
                        );
                      }).toList(),
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
                      child: IndexedStack(
                        index: selectedIndex2,
                        children: profiles.asMap().entries.map((entry) {
                          final index = entry.key;
                          final profile = entry.value;
                          return WebviewContainer(
                            key: ValueKey('split_${profile.id}'),
                            profileId: profile.id,
                            initialUrl: profile.initialUrl,
                            profileName: profile.name,
                            profileIndex: index,
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
      );
  }
}

/// One sidebar row: either a group header label or a profile entry index.
class _SidebarRow {
  final bool isHeader;
  final String? label;
  final int index;

  const _SidebarRow.header(this.label)
      : isHeader = true,
        index = -1;

  const _SidebarRow.item(this.index)
      : isHeader = false,
        label = null;
}
