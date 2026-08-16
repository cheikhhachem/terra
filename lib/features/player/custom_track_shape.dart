// Adapted from Mangayomi's custom_track_shape.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
import 'package:flutter/material.dart';

class PlayerTrackShape extends RoundedRectSliderTrackShape {
  PlayerTrackShape({required this.chapterMarks, required this.duration});

  final List<Duration> chapterMarks;
  final Duration duration;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 2,
    required TextDirection textDirection,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (duration.inMilliseconds <= 0) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()..color = Colors.white;
    for (final mark in chapterMarks) {
      final x =
          rect.left +
          rect.width * mark.inMilliseconds / duration.inMilliseconds;
      context.canvas.drawRect(
        Rect.fromLTWH(x, rect.top, 3, rect.height),
        paint,
      );
    }
  }
}
