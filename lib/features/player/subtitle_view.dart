// Adapted from Mangayomi's subtitle_view.dart and media_kit.
// Sources: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified;
// https://github.com/media-kit/media-kit (MIT), modified.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerSubtitleStyle {
  const PlayerSubtitleStyle({
    this.fontSize = 45,
    this.bold = false,
    this.italic = false,
    this.textColor = Colors.white,
    this.borderColor = Colors.black,
    this.backgroundColor = Colors.transparent,
  });
  final double fontSize;
  final bool bold;
  final bool italic;
  final Color textColor;
  final Color borderColor;
  final Color backgroundColor;

  TextStyle get textStyle => TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.bold : null,
    fontStyle: italic ? FontStyle.italic : null,
    color: textColor,
    backgroundColor: backgroundColor,
    shadows: [
      for (final offset in const [
        Offset(-1.5, -1.5),
        Offset(1.5, -1.5),
        Offset(1.5, 1.5),
        Offset(-1.5, 1.5),
      ])
        Shadow(offset: offset, color: borderColor, blurRadius: 1.4),
    ],
  );
}

class PlayerSubtitleView extends StatefulWidget {
  const PlayerSubtitleView({
    super.key,
    required this.controller,
    this.style = const PlayerSubtitleStyle(),
  });
  final VideoController controller;
  final PlayerSubtitleStyle style;
  @override
  State<PlayerSubtitleView> createState() => _PlayerSubtitleViewState();
}

class _PlayerSubtitleViewState extends State<PlayerSubtitleView> {
  late List<String> subtitle = widget.controller.player.state.subtitle;
  StreamSubscription<List<String>>? subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      if (mounted) setState(() => subtitle = value);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final scale = sqrt(
        (constraints.maxWidth * constraints.maxHeight / (1920 * 1080)).clamp(
          0,
          1,
        ),
      );
      return Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.bottomCenter,
          child: Text(
            subtitle.where((line) => line.trim().isNotEmpty).join('\n'),
            style: widget.style.textStyle,
            textAlign: TextAlign.center,
            textScaler: TextScaler.linear(scale),
          ),
        ),
      );
    },
  );
}
