import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../settings/settings_dialog.dart';
import '../vault/vault_dialog.dart';

/// Navigation / actions toolbar shown under the title bar, mirroring the
/// Electron design: back · forward · reload | split · ⌥ settings/vault ·
/// Ctrl K hint.
class AppToolbar extends ConsumerWidget {
  const AppToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(activeProfileIndexProvider);
    final controllers = ref.watch(webviewControllersProvider);
    final activeController = controllers['main_$selectedIndex'];
    final isSplit = ref.watch(isSplitViewEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    final controller = activeController;

    Widget iconButton({
      required IconData icon,
      required VoidCallback? onPressed,
      String? tooltip,
      bool active = false,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        splashRadius: 16,
        color: onPressed == null
            ? scheme.onSurface.withValues(alpha: 0.3)
            : active
                ? scheme.primary
                : scheme.onSurfaceVariant,
        onPressed: onPressed,
      );
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          iconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: controller?.goBack,
          ),
          iconButton(
            icon: Icons.arrow_forward,
            tooltip: 'Forward',
            onPressed: controller?.goForward,
          ),
          iconButton(
            icon: Icons.refresh,
            tooltip: 'Reload',
            onPressed: controller?.reload,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 1,
            height: 20,
            child: ColoredBox(color: scheme.onSurface.withValues(alpha: 0.1)),
          ),
          const SizedBox(width: 4),
          iconButton(
            icon: Icons.splitscreen_outlined,
            tooltip: 'Split view (Ctrl+Shift+S)',
            active: isSplit,
            onPressed: () {
              if (!isSplit) {
                final profiles = ref.read(profilesProvider);
                final current = ref.read(activeProfileIndexProvider);
                ref
                    .read(activeProfileIndex2Provider.notifier)
                    .setIndex((current + 1) % profiles.length);
              }
              ref.read(isSplitViewEnabledProvider.notifier).toggle();
            },
          ),
          const Spacer(),

          // Ctrl K hint chip (opens the command palette)
          ActionChip(
            avatar: Icon(Icons.search, size: 14, color: scheme.onSurfaceVariant),
            label: Text(
              'Ctrl K',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12)),
            backgroundColor: scheme.surfaceContainerHighest,
            onPressed: () =>
                ref.read(isCommandPaletteOpenProvider.notifier).setOpen(true),
          ),
          const SizedBox(width: 4),
          iconButton(
            icon: Icons.key,
            tooltip: 'Credential vault',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const VaultDialog(),
            ),
          ),
          iconButton(
            icon: Icons.settings,
            tooltip: 'Settings',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
