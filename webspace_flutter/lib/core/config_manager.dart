import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'providers.dart';

/// Loads / saves `config.json` using the same lookup order as the Electron
/// build, and always writes the Electron-compatible *grouped map* format:
///
/// ```json
/// { "Personal (Google)": [ { "name": "Gmail", "url": "..." } ], ... }
/// ```
class ConfigManager {
  static File? _resolved;

  static List<String> get _candidates {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final cwd = Directory.current.path;
    return [
      if (Platform.environment['WEBSPACE_CONFIG']?.isNotEmpty == true)
        Platform.environment['WEBSPACE_CONFIG']!,
      '$cwd/config.json', // running from the repo root
      '$cwd/../config.json', // `flutter run` from webspace_flutter/
      '$home/newapp/config.json', // legacy Electron dev location
      '$home/.my_webapp_data/config.json', // legacy Electron location
      '$home/.config/webspace/config.json', // packaged fallback (Electron userData)
    ];
  }

  /// Resolves (and memoizes) the config file, creating the fallback if the
  /// file does not exist anywhere yet.
  static File getConfigFile() {
    if (_resolved != null) return _resolved!;
    for (final path in _candidates) {
      final file = File(path);
      if (file.existsSync()) {
        _resolved = file;
        return file;
      }
    }
    final file = File(_candidates.last);
    file.parent.createSync(recursive: true);
    _resolved = file;
    return file;
  }

  /// Parses either the Electron grouped-map format or a plain list format.
  static List<AppProfile> parseProfiles(String contents) {
    final dynamic decoded = jsonDecode(contents);
    final profiles = <AppProfile>[];
    var id = 1;

    if (decoded is List) {
      for (final app in decoded) {
        profiles.add(_profileFrom(app, group: null, id: id++));
      }
    } else if (decoded is Map) {
      decoded.forEach((groupName, apps) {
        if (apps is List) {
          for (final app in apps) {
            profiles.add(_profileFrom(app, group: groupName as String, id: id++));
          }
        }
      });
    }
    return profiles;
  }

  static AppProfile _profileFrom(dynamic json, {required String? group, required int id}) {
    final map = json is Map ? json : const {};
    final name = (map['name'] ?? 'App $id').toString();
    final url = (map['url'] ?? map['initialUrl'] ?? 'https://duckduckgo.com').toString();
    return AppProfile(
      id: (map['id'] ?? id).toString(),
      name: name,
      initialUrl: url,
      customCSS: map['customCSS'] as String?,
      group: group,
    );
  }

  /// Loads profiles from the resolved config file and appends the internal
  /// Browser tab (never persisted back to disk).
  static Future<List<AppProfile>> loadProfiles() async {
    try {
      final contents = await getConfigFile().readAsString();
      final profiles = parseProfiles(contents);
      profiles.add(
        const AppProfile(
          id: 'browser_tab',
          name: 'Browser',
          initialUrl: 'https://google.com',
          isBrowser: true,
        ),
      );
      return profiles;
    } catch (e) {
      debugPrint('Error loading config: $e');
      return const [
        AppProfile(id: 'fallback', name: 'Error Loading', initialUrl: 'https://duckduckgo.com')
      ];
    }
  }

  /// Writes profiles back in the Electron grouped-map format so both builds
  /// share one file. The internal Browser tab is never written.
  static Future<void> saveProfiles(List<AppProfile> profiles, {File? toFile}) async {
    final file = toFile ?? getConfigFile();
    final groups = <String, List<Map<String, dynamic>>>{};

    for (final profile in profiles) {
      if (profile.isBrowser) continue;
      final group = profile.group ?? 'Apps';
      (groups[group] ??= []).add({
        'name': profile.name,
        'url': profile.initialUrl,
        if (profile.customCSS != null && profile.customCSS!.isNotEmpty)
          'customCSS': profile.customCSS,
      });
    }

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(groups),
    );
  }
}
