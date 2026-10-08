import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/favicon_service.dart';

/// Renders a site favicon from the local cache (shared with the Electron
/// build) with a letter-tile fallback — never pings Google's s2 service.
class FaviconIcon extends StatefulWidget {
  final String url;
  final String fallbackLetter;
  final double size;
  final Color letterColor;

  const FaviconIcon({
    super.key,
    required this.url,
    required this.fallbackLetter,
    required this.size,
    this.letterColor = Colors.white70,
  });

  @override
  State<FaviconIcon> createState() => _FaviconIconState();
}

class _FaviconIconState extends State<FaviconIcon> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = FaviconService.iconFor(widget.url);
  }

  @override
  void didUpdateWidget(covariant FaviconIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = FaviconService.iconFor(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _letter(),
          );
        }
        return _letter();
      },
    );
  }

  Widget _letter() => Text(
        widget.fallbackLetter.toUpperCase(),
        style: TextStyle(
          fontSize: widget.size * 0.82,
          fontWeight: FontWeight.bold,
          color: widget.letterColor,
        ),
      );
}
