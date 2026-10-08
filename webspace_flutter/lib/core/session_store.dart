import 'dart:convert';
import 'dart:io';

import 'config_manager.dart';

/// Per-session UI state for the Flutter build: active app, split view,
/// sidebar state, last URL per app, zoom and mute.
///
/// Stored as `session.flutter.json` next to config.json — deliberately NOT
/// settings.json (shared with Electron) and NOT session.json (Electron's own
/// session file), so the three schemas never clobber each other.
class SessionData {
  final String? activeAppId;
  final String? activeAppId2;
  final bool splitView;
  final bool sidebarCollapsed;
  final bool sidebarExpanded;
  final Map<String, String> urls;
  final Map<String, double> zoom;
  final Map<String, bool> muted;

  const SessionData({
    this.activeAppId,
    this.activeAppId2,
    this.splitView = false,
    this.sidebarCollapsed = false,
    this.sidebarExpanded = false,
    this.urls = const {},
    this.zoom = const {},
    this.muted = const {},
  });

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        activeAppId: json['activeAppId'] as String?,
        activeAppId2: json['activeAppId2'] as String?,
        splitView: json['splitView'] as bool? ?? false,
        sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? false,
        sidebarExpanded: json['sidebarExpanded'] as bool? ?? false,
        urls: _stringMap(json['urls']),
        zoom: _doubleMap(json['zoom']),
        muted: _boolMap(json['muted']),
      );

  Map<String, dynamic> toJson() => {
        if (activeAppId != null) 'activeAppId': activeAppId,
        if (activeAppId2 != null) 'activeAppId2': activeAppId2,
        'splitView': splitView,
        'sidebarCollapsed': sidebarCollapsed,
        'sidebarExpanded': sidebarExpanded,
        'urls': urls,
        'zoom': zoom,
        'muted': muted,
      };

  /// Drops ids that no longer exist and heals a missing/invalid active app.
  /// [validIds] is the id set of the current profile list.
  SessionData validate(Set<String> validIds) {
    String? fixId(String? id) => (id != null && validIds.contains(id)) ? id : null;
    return SessionData(
      activeAppId: fixId(activeAppId) ??
          (validIds.isNotEmpty ? validIds.first : null),
      activeAppId2: fixId(activeAppId2),
      splitView: splitView,
      sidebarCollapsed: sidebarCollapsed,
      sidebarExpanded: sidebarExpanded,
      urls: Map.fromEntries(
          urls.entries.where((e) => validIds.contains(e.key))),
      zoom: Map.fromEntries(
          zoom.entries.where((e) => validIds.contains(e.key))),
      muted: Map.fromEntries(
          muted.entries.where((e) => validIds.contains(e.key))),
    );
  }

  static Map<String, String> _stringMap(dynamic v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val.toString()))
      : <String, String>{};

  static Map<String, double> _doubleMap(dynamic v) => v is Map
      ? v.map((k, val) =>
          MapEntry(k.toString(), (val as num?)?.toDouble() ?? 1.0))
      : <String, double>{};

  static Map<String, bool> _boolMap(dynamic v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val == true))
      : <String, bool>{};
}

/// Loaded once in main() before runApp; notifiers seed from it.
SessionData initialSession = const SessionData();

class SessionStore {
  /// Next to the resolved config.json (repo dir in dev, XDG fallback when
  /// packaged), so the location tracks ConfigManager's lookup exactly.
  static File file() => File(
      '${ConfigManager.getConfigFile().parent.path}/session.flutter.json');

  static SessionData load() {
    try {
      final f = file();
      if (f.existsSync()) {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map<String, dynamic>) return SessionData.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt session → start fresh
    }
    return const SessionData();
  }

  /// Full overwrite.
  static Future<void> save(SessionData session) async {
    try {
      final f = file();
      f.parent.createSync(recursive: true);
      await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert(session.toJson()));
    } catch (_) {}
  }

  /// Load → apply [patch] → write. Single-isolate, so read-modify-write is
  /// safe enough for this small file.
  static Future<void> patch(Map<String, dynamic> patch) async {
    try {
      final current = load();
      final merged = current.toJson()..addAll(patch);
      await save(SessionData.fromJson(merged));
    } catch (_) {}
  }

  /// Merge helpers for the per-app maps (patch would replace them wholesale).
  static Future<void> setUrl(String profileId, String url) =>
      _patchMap('urls', {profileId: url});

  static Future<void> setZoom(String profileId, double factor) =>
      _patchMap('zoom', {profileId: factor});

  static Future<void> setMuted(String profileId, bool muted) =>
      _patchMap('muted', {profileId: muted});

  static Future<void> _patchMap(String key, Map<String, dynamic> delta) async {
    try {
      final current = load().toJson();
      final existing = current[key];
      final merged = <String, dynamic>{
        if (existing is Map) ...existing,
        ...delta,
      };
      current[key] = merged;
      await save(SessionData.fromJson(current));
    } catch (_) {}
  }
}
