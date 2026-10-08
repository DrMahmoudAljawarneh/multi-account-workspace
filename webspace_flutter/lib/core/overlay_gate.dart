import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native webview overlays paint above EVERY Flutter pixel — dialogs,
/// the find bar, even snackbars. A pane must therefore hide its overlay
/// while any Flutter UI covers it (the command palette already did this;
/// these flags extend the same rule to the rest).
///
/// [isAppDialogOpenProvider] is true while a modal Settings/Vault dialog
/// is on screen. [isTransientNoticeOpenProvider] is true while a short
/// toast (zoom %, mute state, save confirmation) is showing.
class AppDialogOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool open) => state = open;
}

final isAppDialogOpenProvider =
    NotifierProvider<AppDialogOpenNotifier, bool>(
        () => AppDialogOpenNotifier());

class TransientNoticeOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool open) => state = open;
}

final isTransientNoticeOpenProvider =
    NotifierProvider<TransientNoticeOpenNotifier, bool>(
        () => TransientNoticeOpenNotifier());

/// showDialog that keeps [isAppDialogOpenProvider] true for its whole
/// lifetime, so webview overlays stay hidden behind the dialog instead of
/// painting over it. Safe to call without awaiting.
Future<T?> showAppDialog<T>(
    BuildContext context, WidgetRef ref, WidgetBuilder builder) async {
  ref.read(isAppDialogOpenProvider.notifier).set(true);
  try {
    return await showDialog<T>(context: context, builder: builder);
  } finally {
    try {
      ref.read(isAppDialogOpenProvider.notifier).set(false);
    } catch (_) {}
  }
}

/// SnackBar that keeps [isTransientNoticeOpenProvider] true until it is
/// dismissed, so the toast is not painted over by webview overlays.
Future<void> showTransientNotice(BuildContext context, WidgetRef ref,
    String message, {Duration duration = const Duration(seconds: 1)}) async {
  ref.read(isTransientNoticeOpenProvider.notifier).set(true);
  try {
    if (context.mounted) {
      await ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message), duration: duration))
          .closed;
    }
  } finally {
    try {
      ref.read(isTransientNoticeOpenProvider.notifier).set(false);
    } catch (_) {}
  }
}
