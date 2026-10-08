import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'host_match.dart';

/// Credential vault backed by the OS keyring (libsecret / GNOME Keyring),
/// mirroring Electron's `safeStorage` approach: nothing readable at rest
/// without the keyring.
///
/// Entries live under `cred:<appName>` and hold
/// `{"username","password","domain"?}` — `domain` is optional metadata used
/// to match entries to the site being visited (see [findFor]). Entries
/// written before domain support have no `domain` key and still work via
/// name matching.
class VaultService {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'cred:';

  static String _key(String appName) => '$_prefix$appName';

  static VaultCredential? _decode(String appName, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final domain = decoded['domain']?.toString().trim() ?? '';
      return VaultCredential(
        appName: appName,
        username: (decoded['username'] ?? '').toString(),
        password: (decoded['password'] ?? '').toString(),
        domain: domain.isEmpty ? null : domain,
      );
    } catch (_) {
      return null;
    }
  }

  /// Lists stored credentials (passwords are NOT decrypted here — only the
  /// `username` and `domain` fields are read out of the cached JSON).
  static Future<List<VaultEntry>> list() async {
    try {
      final all = await _storage.readAll();
      final entries = <VaultEntry>[];
      all.forEach((key, value) {
        if (!key.startsWith(_prefix)) return;
        final appName = key.substring(_prefix.length);
        var username = '';
        String? domain;
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) {
            username = (decoded['username'] ?? '').toString();
            final d = decoded['domain']?.toString().trim() ?? '';
            if (d.isNotEmpty) domain = d;
          }
        } catch (_) {}
        entries.add(VaultEntry(appName: appName, username: username, domain: domain));
      });
      entries.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<VaultCredential?> get(String appName) async {
    try {
      final raw = await _storage.read(key: _key(appName));
      if (raw == null) return null;
      return _decode(appName, raw);
    } catch (_) {
      return null;
    }
  }

  /// Auto-fill lookup: the entry named after the app wins (profile-scoped,
  /// precise); otherwise any entry whose stored [VaultEntry.domain] matches
  /// the page host (e.g. a generic "Google" credential filling a Gmail
  /// profile's login on `accounts.google.com`).
  static Future<VaultCredential?> findFor({
    required String host,
    required String appName,
  }) async {
    try {
      final byName = await get(appName);
      if (byName != null) return byName;
      if (host.isEmpty) return null;
      final all = await _storage.readAll();
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        final cred = _decode(entry.key.substring(_prefix.length), entry.value);
        if (cred?.domain != null && hostsMatch(host, cred!.domain!)) {
          return cred;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> save({
    required String appName,
    required String username,
    required String password,
    String? domain,
  }) async {
    try {
      final cleanDomain = domain?.trim() ?? '';
      await _storage.write(
        key: _key(appName),
        value: jsonEncode({
          'username': username,
          'password': password,
          if (cleanDomain.isNotEmpty) 'domain': cleanDomain,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String appName) async {
    try {
      await _storage.delete(key: _key(appName));
      return true;
    } catch (_) {
      return false;
    }
  }
}

class VaultEntry {
  final String appName;
  final String username;
  final String? domain;
  const VaultEntry({required this.appName, required this.username, this.domain});
}

class VaultCredential extends VaultEntry {
  final String password;
  const VaultCredential({
    required super.appName,
    required super.username,
    required this.password,
    super.domain,
  });
}
