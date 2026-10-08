import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/viewport.dart';
import '../settings/settings_dialog.dart';
import '../vault/vault_dialog.dart';

/// Modal command palette (Ctrl+K): fuzzy-filtered commands + profiles.
/// Opened by toggling [isCommandPaletteOpenProvider]; the workspace listens
/// and calls this with its own context.
void showCommandPalette(BuildContext context, WidgetRef ref) {
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
              title: 'Find in page…',
              subtitle: 'Search the current app (Ctrl+F)',
              icon: Icons.manage_search,
              run: () =>
                  ref.read(isFindOpenProvider.notifier).setOpen(true),
            ),
            (
              title: 'Zoom in',
              subtitle: 'Bigger content in the current app (Ctrl +)',
              icon: Icons.zoom_in,
              run: () {
                final id = ref.read(activeProfileIdProvider);
                if (id != null) ViewportCommands.zoomIn(ref, id);
              },
            ),
            (
              title: 'Zoom out',
              subtitle: 'Smaller content in the current app (Ctrl -)',
              icon: Icons.zoom_out,
              run: () {
                final id = ref.read(activeProfileIdProvider);
                if (id != null) ViewportCommands.zoomOut(ref, id);
              },
            ),
            (
              title: 'Reset zoom',
              subtitle: 'Back to 100% (Ctrl+0)',
              icon: Icons.search_off,
              run: () {
                final id = ref.read(activeProfileIdProvider);
                if (id != null) ViewportCommands.zoomReset(ref, id);
              },
            ),
            (
              title: 'Toggle audio mute',
              subtitle: 'Silence the current app (Ctrl+Shift+M)',
              icon: Icons.volume_off,
              run: () {
                final id = ref.read(activeProfileIdProvider);
                if (id != null) ViewportCommands.toggleMute(ref, id);
              },
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
                        ref
                            .read(activeProfileIdProvider.notifier)
                            .select(filteredProfiles.first.id);
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
                                ref
                                    .read(activeProfileIdProvider.notifier)
                                    .select(profile.id);
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
    ref.read(isCommandPaletteOpenProvider.notifier).setOpen(false);
    final action = pendingAction;
    pendingAction = null;
    if (action != null) action();
  });
}
