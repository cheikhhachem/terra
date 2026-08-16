// Adapted from Mangayomi's custom_seekbar.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'custom_track_shape.dart';
import 'player_source.dart';

class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.player,
    required this.chapterMarks,
    this.showLabels = true,
    this.onSeekStart,
    this.onSeekEnd,
  });

  final Player player;
  final List<PlayerChapterMark> chapterMarks;
  final bool showLabels;
  final ValueChanged<Duration>? onSeekStart;
  final ValueChanged<Duration>? onSeekEnd;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  late Duration _position = widget.player.state.position;
  late Duration _duration = widget.player.state.duration;
  late Duration _buffer = widget.player.state.buffer;
  Duration? _temporary;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      widget.player.stream.position.listen((v) => _set(() => _position = v)),
      widget.player.stream.duration.listen((v) => _set(() => _duration = v)),
      widget.player.stream.buffer.listen((v) => _set(() => _buffer = v)),
    ]);
  }

  void _set(VoidCallback update) {
    if (mounted) setState(update);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = max(_duration.inMilliseconds.toDouble(), 0).toDouble();
    final shown = _temporary ?? _position;
    final value = shown.inMilliseconds.clamp(0, maxValue).toDouble();
    final slider = Expanded(
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 5),
          trackShape: PlayerTrackShape(
            chapterMarks: widget.chapterMarks.map((e) => e.position).toList(),
            duration: _duration,
          ),
        ),
        child: Slider(
          max: maxValue < 1 ? 1 : maxValue,
          value: value,
          secondaryTrackValue: _buffer.inMilliseconds
              .clamp(0, maxValue < 1 ? 1 : maxValue)
              .toDouble(),
          onChanged: maxValue < 1
              ? null
              : (v) {
                  final target = Duration(milliseconds: v.round());
                  widget.onSeekStart?.call(target - _position);
                  widget.player.seek(target);
                  setState(() => _temporary = target);
                },
          onChangeEnd: (v) {
            final target = Duration(milliseconds: v.round());
            widget.player.seek(target);
            widget.onSeekEnd?.call(target - _position);
            setState(() => _temporary = null);
          },
        ),
      ),
    );
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          if (widget.showLabels) _Time(value: shown, reference: _duration),
          slider,
          if (widget.showLabels) _Time(value: _duration, reference: _duration),
        ],
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.value, required this.reference});
  final Duration value;
  final Duration reference;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    child: Center(
      child: Text(
        formatPlayerTime(value, hours: reference.inHours > 0),
        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1),
      ),
    ),
  );
}

String formatPlayerTime(Duration value, {bool hours = false}) {
  final h = value.inHours;
  final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours ? '$h:$m:$s' : '$m:$s';
}
