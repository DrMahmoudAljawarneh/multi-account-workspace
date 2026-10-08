import 'dart:io';

/// Writes [contents] to [file] atomically: a sibling `.tmp` file is written
/// first, then renamed over the target (same directory, so the rename is a
/// single atomic operation on POSIX). A crash or power loss mid-write can
/// therefore never leave a truncated or half-written config/session/settings
/// file behind — the old complete file simply survives.
Future<void> atomicWrite(File file, String contents) async {
  final parent = file.parent;
  if (!parent.existsSync()) {
    parent.createSync(recursive: true);
  }
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(contents);
  await tmp.rename(file.path);
}
