import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_all/webview_all.dart';

import 'app_settings.dart';
import 'session_store.dart';

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

/// Builds a stable, filesystem/session-safe id from an app's group + name.
/// Deterministic: the same group/name always yields the same id, so unread
/// badges, session URLs, zoom and selection survive restarts and reorders.
/// Collisions (two apps with the same group+name) get a `_2`, `_3` … suffix.
String stableProfileId(String? group, String name, Set<String> taken) {
  final base = '${group ?? ''}_$name'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  var id = base.isEmpty ? 'app' : base;
  var n = 2;
  while (taken.contains(id)) {
    id = '${base.isEmpty ? 'app' : base}_$n';
    n++;
  }
  taken.add(id);
  return id;
}

/// Resolves a profile id to its list index for IndexedStack; unknown/null ids
/// fall back to 0 (the first app is always visible).
int indexForId(List<AppProfile> profiles, String? id) {
  final i = id == null ? -1 : profiles.indexWhere((p) => p.id == id);
  return i < 0 ? 0 : i;
}

/// The profile id that keyboard / toolbar / find interactions currently
/// target: the split pane's app while split view is on and focused, otherwise
/// the main pane's app.
String? activeIdForInteraction({
  required bool splitView,
  required String focusedPane,
  required String? mainId,
  required String? splitId,
}) {
  if (splitView && focusedPane == 'split') return splitId ?? mainId;
  return mainId;
}

/// Registry key (`main_<id>` / `split_<id>`) of the webview that toolbar
/// navigation and find-in-page should drive; null when none exists.
String? controllerKeyForInteraction({
  required bool splitView,
  required String focusedPane,
  required String? mainId,
  required String? splitId,
}) {
  final id = activeIdForInteraction(
    splitView: splitView,
    focusedPane: focusedPane,
    mainId: mainId,
    splitId: splitId,
  );
  if (id == null) return null;
  final splitPane = splitView && focusedPane == 'split' && splitId != null;
  return '${splitPane ? 'split' : 'main'}_$id';
}

/// Convenience for keyboard handlers (reads current provider values).
String? focusedActiveId(WidgetRef ref) => activeIdForInteraction(
      splitView: ref.read(isSplitViewEnabledProvider),
      focusedPane: ref.read(focusedPaneProvider),
      mainId: ref.read(activeProfileIdProvider),
      splitId: ref.read(activeProfileId2Provider),
    );

/// Selects [id] into the pane that interactions currently target: with split
/// view on and the split pane focused, the second pane switches; everywhere
/// else the main pane does (single-pane behavior stays exactly as before).
void selectIntoFocusedPane(WidgetRef ref, String id) {
  final split = ref.read(isSplitViewEnabledProvider);
  final focused = ref.read(focusedPaneProvider);
  if (split && focused == 'split') {
    ref.read(activeProfileId2Provider.notifier).select(id);
  } else {
    ref.read(activeProfileIdProvider.notifier).select(id);
  }
}

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

// 3. Active Profile State — selection is tracked by STABLE PROFILE ID, not
// list index, so reordering/editing apps can't select the wrong pane.
class ActiveProfileIdNotifier extends Notifier<String?> {
  @override
  String? build() => initialSession.activeAppId;

  void select(String? id) => state = id;
}
final activeProfileIdProvider =
    NotifierProvider<ActiveProfileIdNotifier, String?>(
        () => ActiveProfileIdNotifier());

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

// 6. Sidebar State (seeded from the last session)
class SidebarCollapseNotifier extends Notifier<bool> {
  @override
  bool build() => initialSession.sidebarCollapsed;

  void toggle() => state = !state;
}
final isSidebarCollapsedProvider = NotifierProvider<SidebarCollapseNotifier, bool>(() => SidebarCollapseNotifier());

class SidebarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => initialSession.sidebarExpanded;

  void toggle() => state = !state;
}
final isSidebarExpandedProvider = NotifierProvider<SidebarExpandedNotifier, bool>(() => SidebarExpandedNotifier());

// 7. Split View State (seeded from the last session)
class SplitViewNotifier extends Notifier<bool> {
  @override
  bool build() => initialSession.splitView;

  void toggle() {
    state = !state;
    // Split pane focus is meaningless without the split pane
    if (!state) {
      ref.read(focusedPaneProvider.notifier).set('main');
    }
  }
}
final isSplitViewEnabledProvider = NotifierProvider<SplitViewNotifier, bool>(() => SplitViewNotifier());

/// Which pane keyboard / sidebar / palette interactions target while split
/// view is active. 'main' unless the user clicked the split pane's header.
class FocusedPaneNotifier extends Notifier<String> {
  @override
  String build() => initialSession.focusedPane;

  void set(String pane) => state = pane == 'split' ? 'split' : 'main';
}
final focusedPaneProvider =
    NotifierProvider<FocusedPaneNotifier, String>(() => FocusedPaneNotifier());

class ActiveProfileId2Notifier extends Notifier<String?> {
  @override
  String? build() => initialSession.activeAppId2;

  void select(String? id) => state = id;
}
final activeProfileId2Provider =
    NotifierProvider<ActiveProfileId2Notifier, String?>(
        () => ActiveProfileId2Notifier());

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

// 10. Find-in-page overlay (controls visibility only; query lives in the bar)
class FindOverlayNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setOpen(bool isOpen) => state = isOpen;
}
final isFindOpenProvider =
    NotifierProvider<FindOverlayNotifier, bool>(() => FindOverlayNotifier());

// 11. Per-app viewport state (persisted to session.flutter.json)
class ZoomFactorsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => initialSession.zoom;

  double of(String? profileId) => state[profileId] ?? 1.0;

  Future<void> set(String profileId, double factor) async {
    state = {...state, profileId: factor};
    await SessionStore.setZoom(profileId, factor);
  }
}
final zoomFactorsProvider =
    NotifierProvider<ZoomFactorsNotifier, Map<String, double>>(
        () => ZoomFactorsNotifier());

class MutedAppsNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => initialSession.muted;

  bool isMuted(String? profileId) => state[profileId] ?? false;

  Future<void> set(String profileId, bool muted) async {
    state = {...state, profileId: muted};
    await SessionStore.setMuted(profileId, muted);
  }

  Future<void> toggle(String profileId) =>
      set(profileId, !isMuted(profileId));
}
final mutedAppsProvider =
    NotifierProvider<MutedAppsNotifier, Map<String, bool>>(
        () => MutedAppsNotifier());
