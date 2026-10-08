import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/legacy.dart';
import 'package:local_notifier/local_notifier.dart';
import 'core/providers.dart';
import 'core/config_manager.dart';
import 'features/webview/webview_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load profiles from config.json
  initialProfiles = await ConfigManager.loadProfiles();
  
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
    titleBarStyle: TitleBarStyle.hidden, // Hides native title bar
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
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

class WebSpaceApp extends StatelessWidget {
  const WebSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebSpace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6BC0),
          brightness: Brightness.dark,
          surface: const Color(0xFF252526),
        ),
      ),
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
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final profiles = ref.read(profilesProvider);
            final filteredProfiles = profiles
                .where((p) => p.name.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white24, width: 1),
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
                        if (filteredProfiles.isNotEmpty) {
                          final index = profiles.indexOf(filteredProfiles.first);
                          ref.read(activeProfileIndexProvider.notifier).setIndex(index);
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (filteredProfiles.isEmpty)
                      const Text('No profiles found', style: TextStyle(color: Colors.grey))
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredProfiles.length,
                          itemBuilder: (context, index) {
                            final profile = filteredProfiles[index];
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

    return Scaffold(
      body: Column(
          children: [
            // Custom Frameless Window Drag Area
            DragToMoveArea(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
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
                          hoverColor: Colors.red.withOpacity(0.8),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  if (!isSidebarCollapsed)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSidebarExpanded ? 220 : 72,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
                      ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: profiles.length,
                            itemBuilder: (context, index) {
                              final profile = profiles[index];
                              final isSelected = index == selectedIndex;
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
                                                    ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                                    : Colors.white12,
                                                borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                                                border: Border.all(
                                                  color: isSelected 
                                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.5) 
                                                      : Colors.transparent,
                                                  width: 1,
                                                ),
                                                boxShadow: isSelected ? [
                                                  BoxShadow(
                                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                                    blurRadius: 8,
                                                    spreadRadius: 1,
                                                  )
                                                ] : null,
                                              ),
                                              alignment: Alignment.center,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                                                child: Image.network(
                                                  'https://www.google.com/s2/favicons?domain=${Uri.parse(profile.initialUrl).host}&sz=128',
                                                  width: 24,
                                                  height: 24,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (context, error, stackTrace) => Text(
                                                    profile.name.substring(0, 1).toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.bold,
                                                      color: isSelected 
                                                        ? Theme.of(context).colorScheme.primary 
                                                        : Colors.white70,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if ((unreadCounts[profile.id] ?? 0) > 0)
                                              Positioned(
                                                right: -4,
                                                bottom: -4,
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: const Color(0xFF1E1E1E), width: 2),
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Colors.black45,
                                                        blurRadius: 4,
                                                        offset: Offset(0, 2),
                                                      )
                                                    ],
                                                  ),
                                                  child: Text(
                                                    '${unreadCounts[profile.id]}',
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
                                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            softWrap: false,
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
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white12,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: Colors.white70),
                            onPressed: () {
                              ref.read(isCommandPaletteOpenProvider.notifier).setOpen(true);
                            },
                          ),
                        ),
                        // Toggle Expanded Button
                        IconButton(
                          icon: Icon(isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right),
                          color: Colors.white54,
                          onPressed: () {
                            ref.read(isSidebarExpandedProvider.notifier).toggle();
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  if (!isSidebarCollapsed)
                    const VerticalDivider(thickness: 1, width: 1, color: Colors.black26),
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
