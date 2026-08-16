// Adapted from Mangayomi's play_or_pause_button.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerPlayOrPauseButton extends StatefulWidget {
  const PlayerPlayOrPauseButton({
    super.key,
    required this.controller,
    this.focusNode,
    this.iconSize = 65,
  });

  final VideoController controller;
  final FocusNode? focusNode;
  final double iconSize;

  @override
  State<PlayerPlayOrPauseButton> createState() =>
      _PlayerPlayOrPauseButtonState();
}

class _PlayerPlayOrPauseButtonState extends State<PlayerPlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    value: widget.controller.player.state.playing ? 1 : 0,
    duration: const Duration(milliseconds: 200),
  );
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.player.stream.playing.listen(
      (playing) => playing ? _animation.forward() : _animation.reverse(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: widget.focusNode,
    onPressed: widget.controller.player.playOrPause,
    iconSize: widget.iconSize,
    color: Colors.white,
    icon: IgnorePointer(
      child: AnimatedIcon(
        progress: _animation,
        icon: AnimatedIcons.play_pause,
        size: widget.iconSize,
        color: Colors.white,
      ),
    ),
  );
}
