import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'providers.dart';

class ConfigManager {
  static const String _configFileName = 'config.json';

  static Future<File> _getConfigFile() async {
    // For development, point directly to the original Electron config
    return File('/home/drmj/newapp/config.json');
  }

  /// Loads profiles from the config.json file
  static Future<List<AppProfile>> loadProfiles() async {
    try {
      final file = await _getConfigFile();
      final contents = await file.readAsString();
      final dynamic decoded = jsonDecode(contents);
      
      List<AppProfile> loadedProfiles = [];
      if (decoded is List) {
        loadedProfiles = decoded.map((json) => AppProfile(
          id: json['id'] as String,
          name: json['name'] as String,
          initialUrl: json['initialUrl'] as String,
          customCSS: json['customCSS'] as String?,
        )).toList();
      } else if (decoded is Map) {
        int id = 1;
        decoded.forEach((groupName, apps) {
          for (var app in apps) {
            loadedProfiles.add(AppProfile(
              id: id.toString(),
              name: app['name'] as String,
              initialUrl: app['url'] as String,
              customCSS: app['customCSS'] as String?,
            ));
            id++;
          }
        });
      }
      loadedProfiles.add(
        const AppProfile(
          id: 'browser_tab',
          name: 'Browser',
          initialUrl: 'https://google.com',
          isBrowser: true,
        ),
      );
      
      return loadedProfiles;
    } catch (e) {
      print('Error loading config: $e');
      // Fallback
      return const [
        AppProfile(id: 'fallback', name: 'Error Loading', initialUrl: 'https://duckduckgo.com')
      ];
    }
  }

  /// Saves profiles to the config.json file
  static Future<void> saveProfiles(List<AppProfile> profiles) async {
    final file = await _getConfigFile();
    final jsonList = profiles.map((p) => {
      'id': p.id,
      'name': p.name,
      'initialUrl': p.initialUrl,
      if (p.customCSS != null) 'customCSS': p.customCSS,
    }).toList();
    
    await file.writeAsString(jsonEncode(jsonList));
  }
}
