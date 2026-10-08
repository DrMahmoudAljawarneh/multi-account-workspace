import 'package:flutter/material.dart';

/// Modal confirmation used before discarding unsaved editor changes.
/// Returns true only when the user explicitly chooses "Discard".
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  String message =
      'You have unsaved changes. If you close now they will be lost.',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard changes?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        const SizedBox(width: 4),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return result ?? false;
}
