import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credential vault backed by the OS keyring (libsecret / GNOME Keyring),
/// mirroring Electron's `safeStorage` approach: nothing readable at rest
/// without the keyring.
///
/// Entries live under `cred:<appName>` and hold `{"username","password"}`.
class VaultService {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'cred:';

  static String _key(String appName) => '$_prefix$appName';

  /// Lists stored credentials (passwords are NOT decrypted here).
  static Future<List<VaultEntry>> list() async {
    try {
      final all = await _storage.readAll();
      final entries = <VaultEntry>[];
      all.forEach((key, value) {
        if (!key.startsWith(_prefix)) return;
        final appName = key.substring(_prefix.length);
        var username = '';
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) username = (decoded['username'] ?? '').toString();
        } catch (_) {}
        entries.add(VaultEntry(appName: appName, username: username));
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
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return VaultCredential(
        appName: appName,
        username: (decoded['username'] ?? '').toString(),
        password: (decoded['password'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> save({
    required String appName,
    required String username,
    required String password,
  }) async {
    try {
      await _storage.write(
        key: _key(appName),
        value: jsonEncode({'username': username, 'password': password}),
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
  const VaultEntry({required this.appName, required this.username});
}

class VaultCredential extends VaultEntry {
  final String password;
  const VaultCredential({
    required super.appName,
    required super.username,
    required this.password,
  });
}
