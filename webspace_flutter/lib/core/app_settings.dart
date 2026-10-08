import 'dart:convert';
import 'dart:io';

/// App UI settings.
///
/// Deliberately shares `~/.config/webspace/settings.json` with the Electron
/// version so theme / accent / hibernation timeout stay in sync when both
/// builds are installed. Schema: `{theme, accent, hibernateMinutes}`.
class AppSettings {
  final String theme; // 'dark' | 'light' | 'system'
  final String accent; // '#RRGGBB'
  final int hibernateMinutes; // 0 = never hibernate

  const AppSettings({
    required this.theme,
    required this.accent,
    required this.hibernateMinutes,
  });

  static const defaults = AppSettings(
    theme: 'dark',
    accent: '#0078D7',
    hibernateMinutes: 20,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        theme: json['theme'] as String? ?? defaults.theme,
        accent: json['accent'] as String? ?? defaults.accent,
        hibernateMinutes:
            (json['hibernateMinutes'] as num?)?.toInt() ?? defaults.hibernateMinutes,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'accent': accent,
        'hibernateMinutes': hibernateMinutes,
      };

  AppSettings copyWith({String? theme, String? accent, int? hibernateMinutes}) =>
      AppSettings(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        hibernateMinutes: hibernateMinutes ?? this.hibernateMinutes,
      );
}

class SettingsStore {
  static String get filePath {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return '$home/.config/webspace/settings.json';
  }

  static AppSettings load() {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) return AppSettings.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt or unreadable settings fall back to defaults
    }
    return AppSettings.defaults;
  }

  static Future<void> save(AppSettings settings) async {
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (_) {
      // Never let a settings write crash the app
    }
  }
}
