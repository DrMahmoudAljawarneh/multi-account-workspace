import 'dart:convert';
import 'dart:io';

import 'atomic_write.dart';
import 'config_manager.dart';

/// Per-session UI state for the Flutter build: active app, split view,
/// focused pane, sidebar state, last URL per app, zoom, mute and window
/// placement.
///
/// Stored as `session.flutter.json` next to config.json — deliberately NOT
/// settings.json (shared with Electron) and NOT session.json (Electron's own
/// session file), so the three schemas never clobber each other.
class SessionData {
  final String? activeAppId;
  final String? activeAppId2;
  final bool splitView;
  final String focusedPane; // 'main' | 'split'
  final bool sidebarCollapsed;
  final bool sidebarExpanded;
  final Map<String, String> urls;
  final Map<String, double> zoom;
  final Map<String, bool> muted;
  final Map<String, double>? windowBounds; // x, y, width, height
  final bool windowMaximized;

  const SessionData({
    this.activeAppId,
    this.activeAppId2,
    this.splitView = false,
    this.focusedPane = 'main',
    this.sidebarCollapsed = false,
    this.sidebarExpanded = false,
    this.urls = const {},
    this.zoom = const {},
    this.muted = const {},
    this.windowBounds,
    this.windowMaximized = false,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        activeAppId: json['activeAppId'] as String?,
        activeAppId2: json['activeAppId2'] as String?,
        splitView: json['splitView'] as bool? ?? false,
        focusedPane: json['focusedPane'] == 'split' ? 'split' : 'main',
        sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? false,
        sidebarExpanded: json['sidebarExpanded'] as bool? ?? false,
        urls: _stringMap(json['urls']),
        zoom: _doubleMap(json['zoom']),
        muted: _boolMap(json['muted']),
        windowBounds: _bounds(json['window']),
        windowMaximized: json['windowMaximized'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        if (activeAppId != null) 'activeAppId': activeAppId,
        if (activeAppId2 != null) 'activeAppId2': activeAppId2,
        'splitView': splitView,
        'focusedPane': focusedPane,
        'sidebarCollapsed': sidebarCollapsed,
        'sidebarExpanded': sidebarExpanded,
        'urls': urls,
        'zoom': zoom,
        'muted': muted,
        if (windowBounds != null) 'window': windowBounds,
        if (windowMaximized) 'windowMaximized': true,
      };

  /// Drops ids that no longer exist and heals a missing/invalid active app.
  /// [validIds] is the id set of the current profile list.
  SessionData validate(Set<String> validIds) {
    String? fixId(String? id) => (id != null && validIds.contains(id)) ? id : null;
    final activeId = fixId(activeAppId) ??
        (validIds.isNotEmpty ? validIds.first : null);
    final activeId2 = fixId(activeAppId2);
    return SessionData(
      activeAppId: activeId,
      activeAppId2: activeId2,
      splitView: splitView,
      // A remembered split-pane focus is only meaningful while split is on
      // (and while a second pane actually exists).
      focusedPane: (splitView && activeId2 != null && focusedPane == 'split')
          ? 'split'
          : 'main',
      sidebarCollapsed: sidebarCollapsed,
      sidebarExpanded: sidebarExpanded,
      urls: Map.fromEntries(
          urls.entries.where((e) => validIds.contains(e.key))),
      zoom: Map.fromEntries(
          zoom.entries.where((e) => validIds.contains(e.key))),
      muted: Map.fromEntries(
          muted.entries.where((e) => validIds.contains(e.key))),
      windowBounds: windowBounds,
      windowMaximized: windowMaximized,
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

  /// Parses `{x,y,width,height}`; rejects non-finite or absurdly small
  /// rectangles so a corrupt file can never restore an unusable window.
  static Map<String, double>? _bounds(dynamic v) {
    if (v is! Map) return null;
    double field(String k) {
      final value = v[k];
      return value is num ? value.toDouble() : double.nan;
    }
    final bounds = <String, double>{
      'x': field('x'),
      'y': field('y'),
      'width': field('width'),
      'height': field('height'),
    };
    if (bounds.values.any((d) => !d.isFinite)) return null;
    if (bounds['width']! < 200 || bounds['height']! < 200) return null;
    return bounds;
  }
}

/// Loaded once in main() before runApp; notifiers seed from it.
SessionData initialSession = const SessionData();

class SessionStore {
  /// Next to the resolved config.json (repo dir in dev, XDG fallback when
  /// packaged), so the location tracks ConfigManager's lookup exactly.
  static File file({File? toFile}) => toFile ??
      File(
          '${ConfigManager.getConfigFile().parent.path}/session.flutter.json');

  static SessionData load({File? toFile}) {
    try {
      final f = file(toFile: toFile);
      if (f.existsSync()) {
        final decoded = jsonDecode(f.readAsStringSync());
        if (decoded is Map<String, dynamic>) return SessionData.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt session → start fresh
    }
    return const SessionData();
  }

  /// Full overwrite (atomic: temp file + rename).
  static Future<void> save(SessionData session, {File? toFile}) async {
    try {
      final f = file(toFile: toFile);
      f.parent.createSync(recursive: true);
      await atomicWrite(
          f, const JsonEncoder.withIndent('  ').convert(session.toJson()));
    } catch (_) {}
  }

  /// Load → apply [patch] → write. Single-isolate, so read-modify-write is
  /// safe enough for this small file.
  static Future<void> patch(Map<String, dynamic> patch, {File? toFile}) async {
    try {
      final current = load(toFile: toFile);
      final merged = current.toJson()..addAll(patch);
      await save(SessionData.fromJson(merged), toFile: toFile);
    } catch (_) {}
  }

  /// Merge helpers for the per-app maps (patch would replace them wholesale).
  static Future<void> setUrl(String profileId, String url, {File? toFile}) =>
      _patchMap('urls', {profileId: url}, toFile: toFile);

  static Future<void> setZoom(String profileId, double factor, {File? toFile}) =>
      _patchMap('zoom', {profileId: factor}, toFile: toFile);

  static Future<void> setMuted(String profileId, bool muted, {File? toFile}) =>
      _patchMap('muted', {profileId: muted}, toFile: toFile);

  static Future<void> _patchMap(String key, Map<String, dynamic> delta,
      {File? toFile}) async {
    try {
      final current = load(toFile: toFile).toJson();
      final existing = current[key];
      final merged = <String, dynamic>{
        if (existing is Map) ...existing,
        ...delta,
      };
      current[key] = merged;
      await save(SessionData.fromJson(current), toFile: toFile);
    } catch (_) {}
  }
}
