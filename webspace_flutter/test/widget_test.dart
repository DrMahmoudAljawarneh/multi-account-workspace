import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webspace_flutter/core/app_settings.dart';
import 'package:webspace_flutter/core/config_manager.dart';
import 'package:webspace_flutter/core/providers.dart';

void main() {
  group('ConfigManager.parseProfiles', () {
    test('parses the Electron grouped-map format with group names', () {
      const source = '''
      {
        "Personal (Google)": [
          {"name": "Gmail", "url": "https://mail.google.com"},
          {"name": "Drive", "url": "https://drive.google.com", "customCSS": ".x{}"}
        ],
        "Work (Atlassian)": [
          {"name": "Jira", "url": "https://atlassian.net"}
        ]
      }''';

      final profiles = ConfigManager.parseProfiles(source);

      expect(profiles, hasLength(3));
      expect(profiles[0].name, 'Gmail');
      expect(profiles[0].initialUrl, 'https://mail.google.com');
      expect(profiles[0].group, 'Personal (Google)');
      expect(profiles[1].customCSS, '.x{}');
      expect(profiles[2].name, 'Jira');
      expect(profiles[2].group, 'Work (Atlassian)');
    });

    test('parses the legacy flat list format', () {
      const source = '''
      [
        {"name": "Gmail", "url": "https://mail.google.com"},
        {"name": "Old", "initialUrl": "https://example.com"}
      ]''';

      final profiles = ConfigManager.parseProfiles(source);

      expect(profiles, hasLength(2));
      expect(profiles[0].group, isNull);
      expect(profiles[1].initialUrl, 'https://example.com');
    });

    test('survives entries without a url', () {
      final profiles = ConfigManager.parseProfiles('[{"name": "Broken"}]');
      expect(profiles, hasLength(1));
      expect(profiles[0].initialUrl, isNotEmpty);
    });
  });

  group('ConfigManager.saveProfiles', () {
    test('round-trips back to Electron grouped-map format', () async {
      final dir = Directory.systemTemp.createTempSync('webspace_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/config.json');

      const source = '''
      {
        "Personal (Google)": [
          {"name": "Gmail", "url": "https://mail.google.com"}
        ],
        "Work (Atlassian)": [
          {"name": "Jira", "url": "https://atlassian.net", "customCSS": "body{}"}
        ]
      }''';
      final profiles = ConfigManager.parseProfiles(source)
        ..add(const AppProfile(
            id: 'browser_tab', name: 'Browser', initialUrl: 'https://google.com', isBrowser: true));

      await ConfigManager.saveProfiles(profiles, toFile: file);

      final saved = jsonDecode(file.readAsStringSync());
      expect(saved, isA<Map<String, dynamic>>());
      expect((saved as Map).keys, ['Personal (Google)', 'Work (Atlassian)']);

      // The internal Browser tab must never be persisted
      final work = saved['Work (Atlassian)'] as List;
      expect(work.single['url'], 'https://atlassian.net');
      expect(work.single['customCSS'], 'body{}');
      for (final group in saved.values) {
        for (final app in group as List) {
          expect(app['name'], isNot('Browser'));
        }
      }

      // And reloading the saved file yields the same profiles
      final reloaded = ConfigManager.parseProfiles(file.readAsStringSync());
      expect(reloaded.map((p) => p.name), ['Gmail', 'Jira']);
      expect(reloaded.map((p) => p.group),
          ['Personal (Google)', 'Work (Atlassian)']);
    });
  });

  group('AppSettings', () {
    test('parses the shared settings.json schema', () {
      final settings = AppSettings.fromJson(
          jsonDecode('{"theme":"light","accent":"#7C3AED","hibernateMinutes":35}'));
      expect(settings.theme, 'light');
      expect(settings.accent, '#7C3AED');
      expect(settings.hibernateMinutes, 35);
    });

    test('falls back to defaults for missing/garbage fields', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings.theme, AppSettings.defaults.theme);
      expect(settings.accent, AppSettings.defaults.accent);
      expect(settings.hibernateMinutes, AppSettings.defaults.hibernateMinutes);

      final filled = AppSettings.defaults.copyWith(accent: '#FF0000');
      expect(filled.accent, '#FF0000');
      expect(filled.theme, AppSettings.defaults.theme);
    });
  });
}
