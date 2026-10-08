import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Slim header shown above each pane while split view is active.
///
/// It is the pane's focus switch (click to target this pane with sidebar /
/// palette / Ctrl+1..9 / find / toolbar navigation), shows the pane's current
/// app, and hosts the split controls: swap panes on the main header, close
/// split on the second header.
class PaneHeader extends ConsumerWidget {
  final String pane; // 'main' | 'split'

  const PaneHeader({super.key, required this.pane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profiles = ref.watch(profilesProvider);
    final mainId = ref.watch(activeProfileIdProvider);
    final splitId = ref.watch(activeProfileId2Provider);
    final focused = ref.watch(focusedPaneProvider) == pane;

    final id = pane == 'split' ? splitId : mainId;
    final index = id == null ? -1 : indexForId(profiles, id);
    final name =
        id == null || index < 0 || index >= profiles.length ? '—' : profiles[index].name;

    Widget smallButton(IconData icon, String tooltip, VoidCallback onPressed) {
      return SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          icon: Icon(icon, size: 15),
          tooltip: tooltip,
          splashRadius: 12,
          padding: EdgeInsets.zero,
          color: scheme.onSurfaceVariant,
          onPressed: onPressed,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(focusedPaneProvider.notifier).set(pane),
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: BoxDecoration(
          color: focused
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surface,
          border: Border(
            bottom: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: focused ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                  color: focused ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (pane == 'main')
              smallButton(
                Icons.swap_horiz,
                'Swap panes',
                () {
                  if (mainId == null || splitId == null) return;
                  ref.read(activeProfileIdProvider.notifier).select(splitId);
                  ref.read(activeProfileId2Provider.notifier).select(mainId);
                },
              )
            else
              smallButton(
                Icons.close,
                'Close split view',
                () =>
                    ref.read(isSplitViewEnabledProvider.notifier).toggle(),
              ),
          ],
        ),
      ),
    );
  }
}
