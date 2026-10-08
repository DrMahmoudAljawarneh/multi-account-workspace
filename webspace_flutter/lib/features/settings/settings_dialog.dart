import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_settings.dart';
import '../../core/app_version.dart';
import '../../core/config_manager.dart';
import '../../core/providers.dart';
import '../widgets/confirm_dialog.dart';

/// Structured settings manager mirroring the Electron build:
/// Appearance (live theme/accent/hibernation) · Profiles & Apps editor ·
/// Advanced JSON — all persisted to the shared settings.json / config.json.
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

/// One editable app row. Owns its text controllers so focus/selection survive
/// rebuilds and nothing leaks.
class _AppDraft {
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController cssCtrl;
  bool showCss = false;

  _AppDraft({required String name, required String url, String css = ''})
      : nameCtrl = TextEditingController(text: name),
        urlCtrl = TextEditingController(text: url),
        cssCtrl = TextEditingController(text: css);

  factory _AppDraft.fromProfile(AppProfile p) => _AppDraft(
        name: p.name,
        url: p.initialUrl,
        css: p.customCSS ?? '',
      );

  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    cssCtrl.dispose();
  }
}

class _GroupDraft {
  final TextEditingController nameCtrl;
  final List<_AppDraft> apps;

  _GroupDraft({required String name, required this.apps})
      : nameCtrl = TextEditingController(text: name);

  void dispose() {
    nameCtrl.dispose();
    for (final app in apps) {
      app.dispose();
    }
  }
}

class _SettingsDialogState extends ConsumerState<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_GroupDraft> _groups;
  late final TextEditingController _jsonCtrl;
  bool _jsonDirty = false;
  bool _dirty = false; // any unsaved editor / JSON change
  String? _error;

  static const _accents = [
    '#0078D7',
    '#7C3AED',
    '#DB2777',
    '#E11D48',
    '#EA580C',
    '#CA8A04',
    '#16A34A',
    '#0891B2',
    '#64748B',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _groups = _draftsFromProfiles(ref.read(profilesProvider));
    _jsonCtrl = TextEditingController(text: _encodeDrafts(_groups));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _jsonCtrl.dispose();
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- drafts

  static List<_GroupDraft> _draftsFromProfiles(List<AppProfile> profiles) {
    final groups = <String, _GroupDraft>{};
    for (final p in profiles) {
      if (p.isBrowser) continue;
      final groupName = p.group ?? 'Apps';
      groups.putIfAbsent(groupName,
          () => _GroupDraft(name: groupName, apps: []));
      groups[groupName]!.apps.add(_AppDraft.fromProfile(p));
    }
    if (groups.isEmpty) {
      groups['Apps'] = _GroupDraft(name: 'Apps', apps: []);
    }
    return groups.values.toList();
  }

  static String _encodeDrafts(List<_GroupDraft> groups) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final g in groups) {
      map[g.nameCtrl.text] = [
        for (final a in g.apps)
          {
            'name': a.nameCtrl.text,
            'url': a.urlCtrl.text,
            if (a.cssCtrl.text.isNotEmpty) 'customCSS': a.cssCtrl.text,
          },
      ];
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static void _disposeAll(List<_GroupDraft> groups) {
    for (final g in groups) {
      g.dispose();
    }
  }

  void _draftsChanged() {
    _dirty = true;
    _jsonDirty = false;
    _jsonCtrl.text = _encodeDrafts(_groups);
    _error = null;
    setState(() {});
  }

  void _draftEdited() {
    // Text changed — keep the user's JSON edits intact but clear old errors
    setState(() {
      _dirty = true;
      _error = null;
    });
  }

  // ------------------------------------------------------------ appearance

  void _updateSettings(AppSettings next) {
    ref.read(settingsProvider.notifier).update(next);
  }

  static Color _hexToColor(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  // ---------------------------------------------------------------- save

  String? _validate(List<_GroupDraft> groups) {
    final seen = <String>{};
    for (final g in groups) {
      final name = g.nameCtrl.text.trim();
      if (name.isEmpty) return 'Group names cannot be empty';
      if (!seen.add(name.toLowerCase())) return 'Duplicate group name: "$name"';
      for (final a in g.apps) {
        if (a.nameCtrl.text.trim().isEmpty) return 'Every app needs a name';
        final uri = Uri.tryParse(a.urlCtrl.text.trim());
        if (uri == null ||
            !uri.hasScheme ||
            !(uri.isScheme('http') || uri.isScheme('https'))) {
          return '"${a.nameCtrl.text}" has an invalid URL (must start with http:// or https://)';
        }
      }
    }
    return null;
  }

  List<_GroupDraft> _parseJsonDrafts(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('JSON must be an object of group → apps');
    }
    final groups = <_GroupDraft>[];
    decoded.forEach((groupName, apps) {
      final group = _GroupDraft(name: groupName.toString(), apps: []);
      if (apps is List) {
        for (final app in apps) {
          final map = app is Map ? app : const {};
          group.apps.add(_AppDraft(
            name: (map['name'] ?? '').toString(),
            url: (map['url'] ?? '').toString(),
            css: (map['customCSS'] ?? '').toString(),
          ));
        }
      }
      groups.add(group);
    });
    return groups;
  }

  Future<void> _save() async {
    List<_GroupDraft> groups;
    if (_jsonDirty) {
      try {
        groups = _parseJsonDrafts(_jsonCtrl.text);
      } catch (e) {
        setState(() => _error = 'Invalid JSON: $e');
        return;
      }
    } else {
      groups = _groups;
    }

    final error = _validate(groups);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final current = ref.read(profilesProvider);
    final browser = current.where((p) => p.isBrowser).toList();

    // Stable ids derived from group + name (same rule as ConfigManager), so
    // selection, unread badges and session state follow apps across edits.
    final taken = <String>{'browser_tab', 'fallback'};
    final newProfiles = <AppProfile>[
      for (final g in groups)
        for (final a in g.apps)
          AppProfile(
            id: stableProfileId(
                g.nameCtrl.text.trim(), a.nameCtrl.text.trim(), taken),
            name: a.nameCtrl.text.trim(),
            initialUrl: a.urlCtrl.text.trim(),
            customCSS: a.cssCtrl.text.isEmpty ? null : a.cssCtrl.text,
            group: g.nameCtrl.text.trim(),
          ),
      ...browser,
    ];

    final activeId = ref.read(activeProfileIdProvider);
    final activeId2 = ref.read(activeProfileId2Provider);

    ref.read(profilesProvider.notifier).setProfiles(newProfiles);

    // Preserve the current selections by id; heal them if the app was
    // removed or renamed in this edit.
    if (activeId == null || !newProfiles.any((p) => p.id == activeId)) {
      ref.read(activeProfileIdProvider.notifier).select(
          newProfiles.isNotEmpty ? newProfiles.first.id : null);
    }
    if (activeId2 != null && !newProfiles.any((p) => p.id == activeId2)) {
      ref.read(activeProfileId2Provider.notifier).select(null);
    }

    try {
      await ConfigManager.saveProfiles(newProfiles);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not write config.json: $e');
      return;
    }

    if (mounted) {
      _dirty = false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Close button / Cancel — asks before dropping unsaved edits.
  Future<void> _requestClose() async {
    if (!_dirty || await confirmDiscardChanges(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ----------------------------------------------------------------- tabs

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _appearanceTab(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        _sectionTitle(context, 'Theme'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode, size: 16)),
            ButtonSegment(
                value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode, size: 16)),
            ButtonSegment(
                value: 'system',
                label: Text('System'),
                icon: Icon(Icons.computer, size: 16)),
          ],
          selected: {settings.theme},
          onSelectionChanged: (selection) =>
              _updateSettings(settings.copyWith(theme: selection.first)),
        ),
        const SizedBox(height: 8),
        _sectionTitle(context, 'Accent color'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in _accents)
              Tooltip(
                message: hex,
                child: InkWell(
                  onTap: () => _updateSettings(settings.copyWith(accent: hex)),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hexToColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.accent.toUpperCase() == hex
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: settings.accent.toUpperCase() == hex
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
        _sectionTitle(context, 'Hibernation'),
        Slider(
          value: settings.hibernateMinutes.clamp(0, 120).toDouble(),
          min: 0,
          max: 120,
          divisions: 24,
          label: settings.hibernateMinutes == 0
              ? 'Never'
              : '${settings.hibernateMinutes} min',
          onChanged: (value) => _updateSettings(
              settings.copyWith(hibernateMinutes: value.round())),
        ),
        Text(
          settings.hibernateMinutes == 0
              ? 'Apps stay loaded forever (uses more RAM).'
              : 'Inactive apps hibernate after ${settings.hibernateMinutes} minutes to free RAM.',
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _appRow(BuildContext context, int ai, _GroupDraft group) {
    final app = group.apps[ai];
    final scheme = Theme.of(context).colorScheme;

    void move(int delta) {
      final target = ai + delta;
      if (target < 0 || target >= group.apps.length) return;
      final item = group.apps.removeAt(ai);
      group.apps.insert(target, item);
      _draftsChanged();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Name',
                    hintText: 'Gmail',
                  ),
                  style: const TextStyle(fontSize: 13),
                  controller: app.nameCtrl,
                  onChanged: (_) => _draftEdited(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'URL',
                    hintText: 'https://mail.google.com',
                  ),
                  style: const TextStyle(fontSize: 13),
                  controller: app.urlCtrl,
                  onChanged: (_) => _draftEdited(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Custom CSS',
                icon: Icon(Icons.code, size: 17),
                color: app.showCss ? scheme.primary : scheme.onSurfaceVariant,
                splashRadius: 14,
                onPressed: () => setState(() => app.showCss = !app.showCss),
              ),
              IconButton(
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward, size: 16),
                color: scheme.onSurfaceVariant,
                splashRadius: 14,
                onPressed: ai == 0 ? null : () => move(-1),
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward, size: 16),
                color: scheme.onSurfaceVariant,
                splashRadius: 14,
                onPressed: ai == group.apps.length - 1 ? null : () => move(1),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 16),
                color: scheme.error,
                splashRadius: 14,
                onPressed: () {
                  app.dispose();
                  group.apps.removeAt(ai);
                  _draftsChanged();
                },
              ),
            ],
          ),
          if (app.showCss)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(
                    fontSize: 12, fontFamily: 'monospace', height: 1.4),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Custom CSS for this app',
                  border: OutlineInputBorder(),
                ),
                controller: app.cssCtrl,
                onChanged: (_) => _draftEdited(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profilesTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        for (var gi = 0; gi < _groups.length; gi++)
          Builder(builder: (context) {
            final group = _groups[gi];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Group name',
                          ),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                          controller: group.nameCtrl,
                          onChanged: (_) => _draftEdited(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove group',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: scheme.error,
                        splashRadius: 14,
                        onPressed: _groups.length == 1
                            ? null
                            : () {
                                group.dispose();
                                _groups.removeAt(gi);
                                _draftsChanged();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var ai = 0; ai < group.apps.length; ai++)
                    _appRow(context, ai, group),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label:
                        const Text('Add app', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      group.apps.add(_AppDraft(name: '', url: 'https://'));
                      _draftsChanged();
                    },
                  ),
                ],
              ),
            );
          }),
        OutlinedButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined, size: 16),
          label: const Text('Add group'),
          onPressed: () {
            _groups.add(_GroupDraft(name: 'New group', apps: []));
            _draftsChanged();
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _jsonTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Direct access to config.json — the same file the Electron build uses. '
            'An object of "Group name" → [apps]. Saved together with the editor on Save.',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              maxLines: null,
              expands: true,
              minLines: null,
              style: const TextStyle(
                  fontSize: 13, fontFamily: 'monospace', height: 1.5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              controller: _jsonCtrl,
              onChanged: (_) {
                _jsonDirty = true;
                _draftEdited();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.playlist_add_check, size: 16),
              label: const Text('Validate & load into editor'),
              onPressed: () {
                try {
                  final fresh = _parseJsonDrafts(_jsonCtrl.text);
                  final error = _validate(fresh);
                  if (error != null) {
                    _disposeAll(fresh);
                    throw FormatException(error);
                  }
                  _disposeAll(_groups);
                  setState(() {
                    _groups = fresh;
                    _jsonDirty = false;
                    _jsonCtrl.text = _encodeDrafts(_groups);
                    _error = null;
                  });
                } catch (e) {
                  setState(() => _error = 'Invalid JSON: $e');
                }
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        // Esc / back gesture / barrier tap while dirty → confirm first
        if (!didPop) _requestClose();
      },
      child: Dialog(
      child: SizedBox(
        width: 700,
        height: 580,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                children: [
                  Text('Settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    splashRadius: 16,
                    onPressed: _requestClose,
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Appearance'),
                Tab(text: 'Profiles & Apps'),
                Tab(text: 'Advanced JSON'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _appearanceTab(context),
                  _profilesTab(context),
                  _jsonTab(context),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  if (_error != null)
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.error, fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  Text('WebSpace v$kAppVersion',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  TextButton(
                    onPressed: _requestClose,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
