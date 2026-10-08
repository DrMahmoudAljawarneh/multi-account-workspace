import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../widgets/favicon_icon.dart';

/// One sidebar row: either a group header label or a profile entry index.
class SidebarRow {
  final bool isHeader;
  final String? label;
  final int index;

  const SidebarRow.header(this.label)
      : isHeader = true,
        index = -1;

  const SidebarRow.item(this.index)
      : isHeader = false,
        label = null;
}

/// App list sidebar with group headers, unread badges, Franz-style
/// shape-shifting icons and the expand/collapse chevron.
class SidebarPanel extends ConsumerWidget {
  const SidebarPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profiles = ref.watch(profilesProvider);
    final mainId = ref.watch(activeProfileIdProvider);
    final splitId = ref.watch(activeProfileId2Provider);
    final splitOn = ref.watch(isSplitViewEnabledProvider);
    final focusedPane = ref.watch(focusedPaneProvider);
    // Highlight follows the pane that a click will switch — the split pane
    // only when split view is on and focused, the main pane otherwise.
    final activeId = activeIdForInteraction(
      splitView: splitOn,
      focusedPane: focusedPane,
      mainId: mainId,
      splitId: splitId,
    );
    final selectedIndex = indexForId(profiles, activeId);
    final unreadCounts = ref.watch(unreadCountsProvider);
    final isSidebarExpanded = ref.watch(isSidebarExpandedProvider);
    final sidebarColor =
        Color.lerp(scheme.surface, Colors.black, 0.12) ?? scheme.surface;

    // Group headers interleaved with profile entries
    final sidebarRows = <SidebarRow>[];
    String? lastGroup;
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      if (!p.isBrowser && p.group != null && p.group != lastGroup) {
        sidebarRows.add(SidebarRow.header(p.group!));
        lastGroup = p.group;
      }
      sidebarRows.add(SidebarRow.item(i));
    }

    return AnimatedContainer(
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
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                  onTap: () => selectIntoFocusedPane(ref, profile.id),
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
    );
  }
}
