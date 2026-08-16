// Adapted from Mangayomi's widgets/mobile.dart and widgets/desktop.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import 'custom_seekbar.dart';
import 'play_or_pause_button.dart';
import 'player_logic.dart';
import 'player_source.dart';
import 'tv_player_controls.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.source,
    required this.seekIncrement,
    required this.onBack,
    required this.onSettings,
    required this.onFullscreen,
    required this.onFit,
    required this.onEpisodeList,
    required this.onNext,
    required this.onPrevious,
    required this.autoplay,
    required this.onAutoplay,
    required this.desktop,
  });

  final VideoController controller;
  final PlayerSource source;
  final Duration seekIncrement;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onFit;
  final VoidCallback onEpisodeList;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final ValueListenable<bool> autoplay;
  final ValueChanged<bool> onAutoplay;
  final bool desktop;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const _hoverDuration = Duration(seconds: 3);
  Timer? _hideTimer;
  Timer? _tapTimer;
  Timer? _indicatorTimer;
  bool _visible = true;
  bool _mountedControls = true;
  bool _buffering = false;
  bool _doubleSpeed = false;
  double? _oldRate;
  Offset? _dragStart;
  Duration? _dragTarget;
  late final StreamSubscription<bool> _bufferingSub;
  final _playFocus = FocusNode(debugLabel: 'playerPlayPause');
  final _volume = ValueNotifier(0.0);
  final _brightness = ValueNotifier(0.0);
  final _showVolume = ValueNotifier(false);
  final _showBrightness = ValueNotifier(false);

  Player get player => widget.controller.player;

  @override
  void initState() {
    super.initState();
    _buffering = player.state.buffering;
    _bufferingSub = player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });
    _initializeSystemLevels();
    _restartTimer();
  }

  Future<void> _initializeSystemLevels() async {
    try {
      _volume.value = await VolumeController.instance.getVolume();
      VolumeController.instance.showSystemUI = false;
    } catch (_) {}
    try {
      _brightness.value = await ScreenBrightness.instance.application;
    } catch (_) {}
  }

  void _restartTimer() {
    _hideTimer?.cancel();
    if (!_visible)
      setState(() {
        _visible = true;
        _mountedControls = true;
      });
    _hideTimer = Timer(_hoverDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggle() {
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _restartTimer();
    }
  }

  void _seek(Duration delta) {
    var target = player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (player.state.duration > Duration.zero &&
        target > player.state.duration) {
      target = player.state.duration;
    }
    player.seek(target);
  }

  void _dragUpdate(DragUpdateDetails details) {
    _dragStart ??= details.localPosition;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    final delta = details.localPosition.dx - _dragStart!.dx;
    final seconds = delta * duration.inSeconds / 7500;
    setState(() {
      _dragTarget = clampPlayerDuration(
        player.state.position +
            Duration(milliseconds: (seconds * 1000).round()),
        duration,
      );
    });
  }

  void _dragEnd(DragEndDetails details) {
    if (_dragTarget != null) player.seek(_dragTarget!);
    setState(() {
      _dragStart = null;
      _dragTarget = null;
    });
  }

  Future<void> _verticalDrag(DragUpdateDetails details) async {
    final left =
        details.localPosition.dx < MediaQuery.sizeOf(context).width / 2;
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    final next =
        ((left ? _brightness.value : _volume.value) - details.delta.dy / height)
            .clamp(0.0, 1.0);
    if (left) {
      _brightness.value = next;
      _showBrightness.value = true;
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(next);
      } catch (_) {}
    } else {
      _volume.value = next;
      _showVolume.value = true;
      try {
        await VolumeController.instance.setVolume(next);
      } catch (_) {}
    }
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _showBrightness.value = false;
      _showVolume.value = false;
    });
  }

  void _holdStart(LongPressStartDetails details) {
    _oldRate = player.state.rate;
    player.setRate(_oldRate! * 2);
    setState(() => _doubleSpeed = true);
  }

  void _holdEnd(LongPressEndDetails details) {
    if (_oldRate != null) player.setRate(_oldRate!);
    _oldRate = null;
    setState(() => _doubleSpeed = false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tapTimer?.cancel();
    _indicatorTimer?.cancel();
    _bufferingSub.cancel();
    _playFocus.dispose();
    _volume.dispose();
    _brightness.dispose();
    _showVolume.dispose();
    _showBrightness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = MouseRegion(
      onHover: (_) => _restartTimer(),
      cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: Listener(
        onPointerSignal: widget.desktop ? _onScroll : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.desktop ? _desktopTap : _toggle,
          onDoubleTap: widget.desktop ? widget.onFullscreen : null,
          onDoubleTapDown: widget.desktop ? null : _doubleTap,
          onHorizontalDragUpdate: widget.desktop ? null : _dragUpdate,
          onHorizontalDragEnd: widget.desktop ? null : _dragEnd,
          onVerticalDragUpdate: widget.desktop ? null : _verticalDrag,
          onLongPressStart: _holdStart,
          onLongPressEnd: _holdEnd,
          child: Stack(
            children: [
              AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                onEnd: () {
                  if (!_visible && mounted)
                    setState(() => _mountedControls = false);
                },
                child: _mountedControls
                    ? _overlay(context)
                    : const SizedBox.expand(),
              ),
              if (_buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (_dragTarget != null)
                Center(
                  child: _SeekIndicator(
                    target: _dragTarget!,
                    current: player.state.position,
                  ),
                ),
              if (_doubleSpeed)
                const Positioned(
                  top: 30,
                  left: 0,
                  right: 0,
                  child: Center(child: _SpeedIndicator()),
                ),
              if (!widget.desktop) ...[
                _SystemIndicator(
                  show: _showVolume,
                  value: _volume,
                  volume: true,
                ),
                _SystemIndicator(
                  show: _showBrightness,
                  value: _brightness,
                  volume: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!widget.desktop) return body;
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(autofocus: true, child: body),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.space): player.playOrPause,
    const SingleActivator(LogicalKeyboardKey.keyJ): () =>
        _seek(const Duration(seconds: -10)),
    const SingleActivator(LogicalKeyboardKey.keyL): () =>
        _seek(const Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _seek(const Duration(seconds: -5)),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _seek(const Duration(seconds: 5)),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
        player.setVolume((player.state.volume + 5).clamp(0, 100)),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
        player.setVolume((player.state.volume - 5).clamp(0, 100)),
    const SingleActivator(LogicalKeyboardKey.keyF): widget.onFullscreen,
    const SingleActivator(LogicalKeyboardKey.escape): widget.onFullscreen,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): player.play,
    const SingleActivator(LogicalKeyboardKey.mediaPause): player.pause,
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
        player.playOrPause,
  };

  void _onScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      player.setVolume(
        (player.state.volume + (event.scrollDelta.dy < 0 ? 5 : -5)).clamp(
          0,
          100,
        ),
      );
    }
  }

  void _desktopTap() {
    _tapTimer = Timer(const Duration(milliseconds: 100), player.playOrPause);
  }

  void _doubleTap(TapDownDetails details) {
    final forward =
        details.localPosition.dx > MediaQuery.sizeOf(context).width / 2;
    _seek(forward ? widget.seekIncrement : -widget.seekIncrement);
  }

  Widget _overlay(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x61000000), Color(0x00000000), Color(0x61000000)],
            ),
          ),
        ),
      ),
      SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: widget.desktop
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        const Spacer(flex: 3),
                        IconButton(
                          onPressed: widget.onPrevious,
                          icon: const Icon(
                            Icons.skip_previous,
                            size: 35,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        PlayerPlayOrPauseButton(
                          controller: widget.controller,
                          focusNode: _playFocus,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: widget.onNext,
                          icon: const Icon(
                            Icons.skip_next,
                            size: 35,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(flex: 3),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: PlayerSeekBar(
                player: player,
                chapterMarks: widget.source.chapterMarks,
                showLabels: !widget.desktop,
                onSeekStart: (_) => _hideTimer?.cancel(),
                onSeekEnd: (_) => _restartTimer(),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    ],
  );

  Widget _topBar() => Row(
    children: [
      IconButton(
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back, color: Colors.white),
      ),
      Expanded(
        child: ListTile(
          dense: true,
          title: Text(
            widget.source.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            widget.source.episodeLabel,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: widget.autoplay,
        builder: (_, enabled, child) => Tooltip(
          message: 'Autoplay next episode: ${enabled ? 'on' : 'off'}',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onAutoplay(!enabled),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: AutoplaySwitch(
                on: enabled,
                accent: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      if (widget.source.episodes.isNotEmpty)
        IconButton(
          tooltip: 'Episodes',
          onPressed: widget.onEpisodeList,
          icon: const Icon(Icons.playlist_play, color: Colors.white),
        ),
    ],
  );

  Widget _bottomBar() => Padding(
    padding: EdgeInsets.only(bottom: widget.desktop ? 0 : 24),
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: SizedBox(
            height: 35,
            child: ElevatedButton(
              style: widget.desktop
                  ? null
                  : ElevatedButton.styleFrom(
                      minimumSize: const Size(48, 35),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12, height: 1),
                    ),
              onPressed: widget.source.customActions.isEmpty
                  ? () => _seek(widget.source.skipIntro)
                  : widget.source.customActions.first.onPressed,
              onLongPress: widget.source.customActions.isEmpty
                  ? null
                  : widget.source.customActions.first.onLongPress,
              child: Text(
                widget.source.customActions.isEmpty
                    ? '+${widget.source.skipIntro.inSeconds}'
                    : widget.source.customActions.first.label,
              ),
            ),
          ),
        ),
        if (widget.desktop) ...[
          IconButton(
            onPressed: widget.onPrevious,
            icon: const Icon(Icons.skip_previous, color: Colors.white),
          ),
          PlayerPlayOrPauseButton(controller: widget.controller, iconSize: 25),
          IconButton(
            onPressed: widget.onNext,
            icon: const Icon(Icons.skip_next, color: Colors.white),
          ),
          IconButton(
            onPressed: () => _seek(-widget.seekIncrement),
            icon: const Icon(Icons.rotate_left, color: Colors.white),
          ),
          IconButton(
            onPressed: () => _seek(widget.seekIncrement),
            icon: const Icon(Icons.rotate_right, color: Colors.white),
          ),
          _VolumeButton(player: player),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (_, snapshot) => Text(
              formatPlayerTime(snapshot.data ?? Duration.zero),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
        const Spacer(),
        if (widget.source.customActions.length > 1)
          PopupMenuButton<PlayerCustomAction>(
            tooltip: 'Custom buttons',
            icon: const Icon(Icons.terminal, color: Colors.white),
            onSelected: (action) => action.onPressed(),
            itemBuilder: (_) => [
              for (final action in widget.source.customActions)
                PopupMenuItem(value: action, child: Text(action.label)),
            ],
          ),
        IconButton(
          onPressed: widget.onSettings,
          icon: const Icon(Icons.video_settings, color: Colors.white),
        ),
        IconButton(
          onPressed: widget.onFit,
          icon: const Icon(Icons.fit_screen, color: Colors.white),
        ),
        IconButton(
          onPressed: widget.onFullscreen,
          icon: const Icon(Icons.fullscreen, color: Colors.white),
        ),
      ],
    ),
  );
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: player.stream.volume,
    initialData: player.state.volume,
    builder: (_, snap) => IconButton(
      onPressed: () => player.setVolume((snap.data ?? 0) == 0 ? 100 : 0),
      icon: Icon(
        (snap.data ?? 0) == 0 ? Icons.volume_off : Icons.volume_up,
        color: Colors.white,
      ),
    ),
  );
}

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({required this.target, required this.current});
  final Duration target;
  final Duration current;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        formatPlayerTime(target),
        style: const TextStyle(
          fontSize: 65,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        '[${target >= current ? '+' : '-'}${formatPlayerTime((target - current).abs())}]',
        style: const TextStyle(
          fontSize: 40,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _SpeedIndicator extends StatelessWidget {
  const _SpeedIndicator();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '2X',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(width: 6),
          Icon(Icons.fast_forward, color: Colors.white),
        ],
      ),
    ),
  );
}

class _SystemIndicator extends StatelessWidget {
  const _SystemIndicator({
    required this.show,
    required this.value,
    required this.volume,
  });
  final ValueListenable<bool> show;
  final ValueListenable<double> value;
  final bool volume;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: show,
    builder: (_, visible, child) => IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: volume ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ValueListenableBuilder<double>(
              valueListenable: value,
              builder: (_, level, child) => Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(level * 100).ceil()}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    RotatedBox(
                      quarterTurns: -1,
                      child: SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(value: level),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      volume ? Icons.volume_up : Icons.brightness_high,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
