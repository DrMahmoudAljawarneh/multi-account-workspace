import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Frameless window drag strip with minimize / maximize / close controls,
/// rendered above the toolbar.
class AppTitlebar extends StatelessWidget {
  const AppTitlebar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16.0),
              child: Text('WebSpace', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.minimize, size: 16),
                  onPressed: () => windowManager.minimize(),
                  splashRadius: 16,
                ),
                IconButton(
                  icon: const Icon(Icons.crop_square, size: 16),
                  onPressed: () async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  },
                  splashRadius: 16,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => windowManager.close(),
                  splashRadius: 16,
                  hoverColor: Colors.red.withValues(alpha: 0.8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
