import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Floating find-in-page bar overlaying the top-right of the workspace.
/// Uses the page's native window.find() for match navigation (WebKit
/// selects/scrolls to the match); Enter = next, Shift+Enter = prev, Esc = close.
class FindBar extends ConsumerStatefulWidget {
  const FindBar({super.key});

  @override
  ConsumerState<FindBar> createState() => _FindBarState();
}

class _FindBarState extends ConsumerState<FindBar> {
  final _ctrl = TextEditingController();
  bool _noMatch = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run({required bool forward, bool fromTop = false}) async {
    final term = _ctrl.text;
    if (term.isEmpty) {
      setState(() => _noMatch = false);
      return;
    }
    final activeId = ref.read(activeProfileIdProvider);
    if (activeId == null) return;
    final controller =
        ref.read(webviewControllersProvider)['main_$activeId'];
    if (controller == null) return;

    // window.find(searchString, caseSensitive, backwards, wrapAround,
    //            searchInFrames, showDialog)
    if (fromTop) {
      try {
        await controller.runJavaScript('window.getSelection().removeAllRanges();');
      } catch (_) {}
    }
    Object? found;
    try {
      found = await controller.runJavaScriptReturningResult(
          'window.find(${jsonLiteral(term)}, false, ${!forward}, true, false, false);');
    } catch (_) {
      return;
    }
    final hit = found == true || found == 'true';
    if (mounted) {
      setState(() => _noMatch = !hit);
    }
  }

  void _close() {
    final activeId = ref.read(activeProfileIdProvider);
    if (activeId != null) {
      final controller =
          ref.read(webviewControllersProvider)['main_$activeId'];
      controller
          ?.runJavaScript('window.getSelection().removeAllRanges();')
          .catchError((_) {});
    }
    ref.read(isFindOpenProvider.notifier).setOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeId = ref.watch(activeProfileIdProvider);
    final hasController = activeId != null &&
        ref.watch(webviewControllersProvider).containsKey('main_$activeId');

    return Container(
      width: 340,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            _run(forward: !HardwareKeyboard.instance.isShiftPressed);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 16),
            const SizedBox(width: 6),
            SizedBox(
              width: 170,
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                enabled: hasController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _noMatch ? 'No matches' : 'Find in page…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: _noMatch ? scheme.error : null,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (_) => _run(forward: true, fromTop: true),
              ),
            ),
            IconButton(
              tooltip: 'Previous (Shift+Enter)',
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              splashRadius: 14,
              onPressed: hasController ? () => _run(forward: false) : null,
            ),
            IconButton(
              tooltip: 'Next (Enter)',
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              splashRadius: 14,
              onPressed: hasController ? () => _run(forward: true) : null,
            ),
            IconButton(
              tooltip: 'Close (Esc)',
              icon: const Icon(Icons.close, size: 16),
              splashRadius: 14,
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal JS string literal escaping (JSON string rules).
String jsonLiteral(String value) => jsonEncode(value);
