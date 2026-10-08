import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webspace_flutter/core/atomic_write.dart';
import 'package:webspace_flutter/core/host_match.dart';
import 'package:webspace_flutter/core/providers.dart';
import 'package:webspace_flutter/core/session_store.dart';

void main() {
  group('stableProfileId', () {
    test('is deterministic and slug-shaped', () {
      final a = stableProfileId('Personal (Google)', 'Gmail', {});
      final b = stableProfileId('Personal (Google)', 'Gmail', {});
      expect(a, b);
      expect(a, 'personal_google_gmail');
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(a), isTrue);
    });

    test('deduplicates collisions with numeric suffixes', () {
      final taken = <String>{};
      final first = stableProfileId(null, 'Teams', taken);
      final second = stableProfileId('Work', 'Teams', taken);
      final third = stableProfileId('Work', 'Teams', taken);
      expect(first, 'teams');
      expect(second, isNot(first));
      expect(third, isNot(first));
      expect(third, isNot(second));
      expect(taken, {first, second, third});
    });

    test('handles empty and pathological names', () {
      final taken = <String>{};
      expect(stableProfileId(null, '', taken), 'app');
      expect(stableProfileId(null, '   ', taken), 'app_2');
      expect(stableProfileId('', '***', taken), 'app_3');
    });
  });

  group('indexForId', () {
    final profiles = const [
      AppProfile(id: 'a', name: 'A', initialUrl: 'https://a.example'),
      AppProfile(id: 'b', name: 'B', initialUrl: 'https://b.example'),
    ];

    test('resolves known ids', () {
      expect(indexForId(profiles, 'a'), 0);
      expect(indexForId(profiles, 'b'), 1);
    });

    test('falls back to 0 for unknown/null ids', () {
      expect(indexForId(profiles, 'zzz'), 0);
      expect(indexForId(profiles, null), 0);
      expect(indexForId(const [], 'a'), 0);
    });
  });

  group('focused-pane routing helpers', () {
    test('single pane always targets main', () {
      expect(
        activeIdForInteraction(
            splitView: false,
            focusedPane: 'split',
            mainId: 'm',
            splitId: 's'),
        'm',
      );
      expect(
        controllerKeyForInteraction(
            splitView: false,
            focusedPane: 'split',
            mainId: 'm',
            splitId: 's'),
        'main_m',
      );
    });

    test('split view follows the focused pane', () {
      expect(
        activeIdForInteraction(
            splitView: true,
            focusedPane: 'split',
            mainId: 'm',
            splitId: 's'),
        's',
      );
      expect(
        controllerKeyForInteraction(
            splitView: true,
            focusedPane: 'split',
            mainId: 'm',
            splitId: 's'),
        'split_s',
      );
      expect(
        controllerKeyForInteraction(
            splitView: true,
            focusedPane: 'main',
            mainId: 'm',
            splitId: 's'),
        'main_m',
      );
    });

    test('split focus without a split app degrades to main', () {
      expect(
        activeIdForInteraction(
            splitView: true, focusedPane: 'split', mainId: 'm', splitId: null),
        'm',
      );
      expect(
        controllerKeyForInteraction(
            splitView: true, focusedPane: 'split', mainId: 'm', splitId: null),
        'main_m',
      );
      expect(
        controllerKeyForInteraction(
            splitView: true, focusedPane: 'split', mainId: null, splitId: null),
        isNull,
      );
    });
  });

  group('SessionData', () {
    test('round-trips through JSON including window + focus state', () {
      const original = SessionData(
        activeAppId: 'gmail',
        activeAppId2: 'drive',
        splitView: true,
        focusedPane: 'split',
        sidebarCollapsed: true,
        urls: {'gmail': 'https://mail.google.com/mail/u/0'},
        zoom: {'gmail': 1.2},
        muted: {'drive': true},
        windowBounds: {'x': 10.0, 'y': 20.0, 'width': 1280.0, 'height': 800.0},
        windowMaximized: true,
      );
      final restored = SessionData.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(restored.activeAppId, 'gmail');
      expect(restored.activeAppId2, 'drive');
      expect(restored.splitView, isTrue);
      expect(restored.focusedPane, 'split');
      expect(restored.sidebarCollapsed, isTrue);
      expect(restored.urls['gmail'], 'https://mail.google.com/mail/u/0');
      expect(restored.zoom['gmail'], 1.2);
      expect(restored.muted['drive'], isTrue);
      expect(restored.windowBounds?['width'], 1280.0);
      expect(restored.windowBounds?['x'], 10.0);
      expect(restored.windowMaximized, isTrue);
    });

    test('validate heals stale ids and prunes dead entries', () {
      const raw = SessionData(
        activeAppId: 'gone',
        activeAppId2: 'alsoGone',
        splitView: true,
        focusedPane: 'split',
        urls: {'gone': 'https://x', 'kept': 'https://y'},
        zoom: {'gone': 2.0},
        muted: {'kept': true},
      );
      final v = raw.validate({'kept'});
      expect(v.activeAppId, 'kept');
      expect(v.activeAppId2, isNull);
      // Focus can't point at a pane that no longer exists
      expect(v.focusedPane, 'main');
      // …and neither can the split view itself
      expect(v.splitView, isFalse);
      expect(v.urls.keys, ['kept']);
      expect(v.zoom.keys, isEmpty);
      expect(v.muted['kept'], isTrue);
    });

    test('rejects corrupt window bounds instead of restoring garbage', () {
      final tiny = SessionData.fromJson(
          const {'window': {'x': 0, 'y': 0, 'width': 50, 'height': 40}});
      expect(tiny.windowBounds, isNull);

      final garbage = SessionData.fromJson(
          const {'window': {'x': 0, 'y': 'nope', 'width': 900, 'height': 700}});
      expect(garbage.windowBounds, isNull);

      final nonsenseFocus = SessionData.fromJson(const {'focusedPane': 'x'});
      expect(nonsenseFocus.focusedPane, 'main');
    });
  });

  group('SessionStore file operations', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('webspace_session_test');
      file = File('${dir.path}/session.flutter.json');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('save → load round-trips and leaves no temp files behind', () async {
      await SessionStore.save(
        const SessionData(activeAppId: 'gmail', splitView: true),
        toFile: file,
      );
      final loaded = SessionStore.load(toFile: file);
      expect(loaded.activeAppId, 'gmail');
      expect(loaded.splitView, isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('patch merges without dropping other keys', () async {
      await SessionStore.save(
        const SessionData(activeAppId: 'gmail', sidebarCollapsed: true),
        toFile: file,
      );
      await SessionStore.patch({'activeAppId': 'drive'}, toFile: file);
      final loaded = SessionStore.load(toFile: file);
      expect(loaded.activeAppId, 'drive');
      expect(loaded.sidebarCollapsed, isTrue);
    });

    test('setUrl / setZoom / setMuted merge into their per-app maps',
        () async {
      await SessionStore.setUrl('a', 'https://a', toFile: file);
      await SessionStore.setUrl('b', 'https://b', toFile: file);
      await SessionStore.setZoom('a', 1.5, toFile: file);
      await SessionStore.setMuted('b', true, toFile: file);
      // A later write to one map must not erase the others
      await SessionStore.setUrl('a', 'https://a2', toFile: file);

      final loaded = SessionStore.load(toFile: file);
      expect(loaded.urls, {'a': 'https://a2', 'b': 'https://b'});
      expect(loaded.zoom['a'], 1.5);
      expect(loaded.muted['b'], isTrue);
    });

    test('corrupt session file falls back to an empty session', () {
      file.writeAsStringSync('{ not json ]');
      final loaded = SessionStore.load(toFile: file);
      expect(loaded.activeAppId, isNull);
      expect(loaded.splitView, isFalse);
    });
  });

  group('atomicWrite', () {
    test('replaces the target completely and cleans up the temp file',
        () async {
      final dir = Directory.systemTemp.createTempSync('webspace_atomic_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/out.json');

      await atomicWrite(file, '{"v": 1}');
      expect(file.readAsStringSync(), '{"v": 1}');

      await atomicWrite(file, '{"v": 2}');
      expect(file.readAsStringSync(), '{"v": 2}');
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      expect(dir.listSync().length, 1); // only the target file remains
    });
  });

  group('registrableDomain / hostsMatch', () {
    test('groups subdomains under the base domain', () {
      expect(registrableDomain('mail.google.com'), 'google.com');
      expect(registrableDomain('www.google.com'), 'google.com');
      expect(registrableDomain('accounts.google.com'), 'google.com');
      expect(hostsMatch('mail.google.com', 'accounts.google.com'), isTrue);
    });

    test('knows common two-part public suffixes', () {
      expect(registrableDomain('mail.example.co.uk'), 'example.co.uk');
      expect(
          hostsMatch('mail.example.co.uk', 'login.example.co.uk'), isTrue);
      expect(hostsMatch('example.co.uk', 'evil.co.uk'), isFalse);
    });

    test('different domains never match', () {
      expect(hostsMatch('example.com', 'example.net'), isFalse);
      expect(hostsMatch('google.com', 'google.com.evil.org'), isFalse);
      expect(hostsMatch('', 'google.com'), isFalse);
      expect(hostsMatch('google.com', ''), isFalse);
    });

    test('localhost and IPs match only exactly', () {
      expect(hostsMatch('localhost', 'localhost'), isTrue);
      expect(hostsMatch('192.168.1.5', '192.168.1.5'), isTrue);
      expect(hostsMatch('192.168.1.5', '192.168.2.5'), isFalse);
    });

    test('trailing dots and case are normalized', () {
      expect(hostsMatch('Mail.Google.COM.', 'google.com'), isTrue);
    });
  });
}
