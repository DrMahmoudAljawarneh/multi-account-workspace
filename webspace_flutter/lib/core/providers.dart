import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_all/webview_all.dart';

import 'app_settings.dart';

// 1. Data Models
class AppProfile {
  final String id;
  final String name;
  final String initialUrl;
  final String? customCSS;
  final bool isBrowser;
  final String? group; // config group header, e.g. "Personal (Google)"

  const AppProfile({
    required this.id,
    required this.name,
    required this.initialUrl,
    this.customCSS,
    this.isBrowser = false,
    this.group,
  });
}

// Global initial profiles loaded from config.json before runApp
List<AppProfile> initialProfiles = [];

// Global initial settings loaded before runApp
AppSettings initialSettings = AppSettings.defaults;

// 2. Pre-defined Profiles State
class ProfilesNotifier extends Notifier<List<AppProfile>> {
  @override
  List<AppProfile> build() {
    return initialProfiles;
  }

  void setProfiles(List<AppProfile> newProfiles) {
    state = newProfiles;
  }
}
final profilesProvider = NotifierProvider<ProfilesNotifier, List<AppProfile>>(() => ProfilesNotifier());

// 3. Active Profile State
class ActiveProfileIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}
final activeProfileIndexProvider = NotifierProvider<ActiveProfileIndexNotifier, int>(() => ActiveProfileIndexNotifier());

// 4. Command Palette State (Controls visibility)
class CommandPaletteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setOpen(bool isOpen) => state = isOpen;
}
final isCommandPaletteOpenProvider = NotifierProvider<CommandPaletteNotifier, bool>(() => CommandPaletteNotifier());

// 5. Unread Counts State
class UnreadCountsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => {};

  void updateCount(String profileId, int count) {
    if (state[profileId] != count) {
      state = {...state, profileId: count};
    }
  }
}
final unreadCountsProvider = NotifierProvider<UnreadCountsNotifier, Map<String, int>>(() => UnreadCountsNotifier());

// 6. Sidebar State
class SidebarCollapseNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
final isSidebarCollapsedProvider = NotifierProvider<SidebarCollapseNotifier, bool>(() => SidebarCollapseNotifier());

class SidebarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
final isSidebarExpandedProvider = NotifierProvider<SidebarExpandedNotifier, bool>(() => SidebarExpandedNotifier());

// 7. Split View State
class SplitViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
final isSplitViewEnabledProvider = NotifierProvider<SplitViewNotifier, bool>(() => SplitViewNotifier());

class ActiveProfileIndex2Notifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setIndex(int? index) => state = index;
}
final activeProfileIndex2Provider = NotifierProvider<ActiveProfileIndex2Notifier, int?>(() => ActiveProfileIndex2Notifier());

class SplitDividerPositionNotifier extends Notifier<double> {
  @override
  double build() => 0.5;

  void setPosition(double position) {
    if (position >= 0.1 && position <= 0.9) {
      state = position;
    }
  }
}
final splitDividerPositionProvider = NotifierProvider<SplitDividerPositionNotifier, double>(() => SplitDividerPositionNotifier());

// 8. App Settings State (theme / accent / hibernation)
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => initialSettings;

  Future<void> update(AppSettings next) async {
    state = next;
    await SettingsStore.save(next);
  }

  void patch(AppSettings Function(AppSettings) transform) {
    update(transform(state));
  }
}
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
    () => SettingsNotifier());

// 9. Registered webview controllers so the toolbar can drive navigation of
// the currently visible panes (keyed like "main_<profileId>" / "split_<id>").
class WebviewControllersNotifier extends Notifier<Map<String, WebViewController>> {
  @override
  Map<String, WebViewController> build() => {};

  void register(String key, WebViewController controller) {
    state = {...state, key: controller};
  }

  void unregister(String key) {
    if (!state.containsKey(key)) return;
    final next = {...state}..remove(key);
    state = next;
  }
}
final webviewControllersProvider =
    NotifierProvider<WebviewControllersNotifier, Map<String, WebViewController>>(
        () => WebviewControllersNotifier());
