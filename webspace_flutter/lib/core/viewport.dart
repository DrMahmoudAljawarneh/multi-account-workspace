import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Commands that adjust the visible viewport of a profile's webview(s):
/// zoom (CSS zoom on the document) and audio mute (best-effort JS mute with
/// a MutationObserver so newly added media stays muted).
class ViewportCommands {
  /// Mute / unmute script. `__WS_MUTED__` is replaced with true/false.
  static const _muteScript = '''
(() => {
  const apply = (on) => {
    document.querySelectorAll('video,audio').forEach(m => { try { m.muted = on; } catch (e) {} });
    if (on && !window.__wsMuteObs && typeof MutationObserver !== 'undefined') {
      window.__wsMuteObs = new MutationObserver(() => {
        document.querySelectorAll('video,audio').forEach(m => { try { m.muted = true; } catch (e) {} });
      });
      window.__wsMuteObs.observe(document.documentElement, {subtree: true, childList: true});
    } else if (!on && window.__wsMuteObs) {
      window.__wsMuteObs.disconnect();
      window.__wsMuteObs = null;
    }
  };
  apply(__WS_MUTED__);
})();
''';

  /// Runs [js] on every initialized pane showing [profileId].
  static Future<void> _runJs(
      WidgetRef ref, String profileId, String js) async {
    final controllers = ref.read(webviewControllersProvider);
    for (final key in ['main_$profileId', 'split_$profileId']) {
      final c = controllers[key];
      if (c == null) continue;
      try {
        await c.runJavaScript(js);
      } catch (_) {
        // Controller may be disposing/hibernating — ignore
      }
    }
  }

  static Future<double> _set(
      WidgetRef ref, String profileId, double? absolute) async {
    final notifier = ref.read(zoomFactorsProvider.notifier);
    final current = notifier.of(profileId);
    final next = absolute == null ? 1.0 : (current + absolute).clamp(0.5, 2.0);
    await notifier.set(profileId, next);
    await _runJs(ref, profileId,
        'document.documentElement.style.zoom = ${next.toStringAsFixed(2)};');
    return next;
  }

  /// Returns the new zoom factor (for toasts).
  static Future<double> zoomIn(WidgetRef ref, String profileId) =>
      _set(ref, profileId, 0.1);

  static Future<double> zoomOut(WidgetRef ref, String profileId) =>
      _set(ref, profileId, -0.1);

  static Future<double> zoomReset(WidgetRef ref, String profileId) =>
      _set(ref, profileId, null);

  static Future<void> toggleMute(WidgetRef ref, String profileId) async {
    final notifier = ref.read(mutedAppsProvider.notifier);
    final next = !notifier.isMuted(profileId);
    await notifier.set(profileId, next);
    await _runJs(
        ref, profileId, _muteScript.replaceAll('__WS_MUTED__', '$next'));
  }

  /// Re-applies persisted zoom + mute after a page (re)load.
  static Future<void> reapplyOnLoad(
      WidgetRef ref, String profileId, Future<void> Function(String) runJs) async {
    final zoom = ref.read(zoomFactorsProvider.notifier).of(profileId);
    final muted = ref.read(mutedAppsProvider.notifier).isMuted(profileId);
    if (zoom != 1.0) {
      try {
        await runJs('document.documentElement.style.zoom = ${zoom.toStringAsFixed(2)};');
      } catch (_) {}
    }
    if (muted) {
      try {
        await runJs(_muteScript.replaceAll('__WS_MUTED__', 'true'));
      } catch (_) {}
    }
  }
}
