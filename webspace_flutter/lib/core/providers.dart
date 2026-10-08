import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Data Models
class AppProfile {
  final String id;
  final String name;
  final String initialUrl;
  final String? customCSS;
  final bool isBrowser;

  const AppProfile({
    required this.id, 
    required this.name, 
    required this.initialUrl, 
    this.customCSS,
    this.isBrowser = false,
  });
}

// Global initial profiles loaded from config.json before runApp
List<AppProfile> initialProfiles = [];

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
