// Adapted from Mangayomi's tv_player_controls.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'custom_seekbar.dart';
import 'player_logic.dart';
import 'player_session.dart';
import 'player_source.dart';

class TvPlayerControls extends StatefulWidget {
  const TvPlayerControls({
    super.key,
    required this.player,
    required this.source,
    required this.currentQuality,
    required this.speed,
    required this.autoplay,
    required this.onBack,
    required this.onQuality,
    required this.onRate,
    required this.onAutoplay,
    required this.onSettings,
    required this.onEpisodeList,
    required this.onNext,
  });

  final Player player;
  final PlayerSource source;
  final PlayerQuality currentQuality;
  final ValueListenable<double> speed;
  final ValueListenable<bool> autoplay;
  final VoidCallback onBack;
  final ValueChanged<PlayerQuality> onQuality;
  final ValueChanged<double> onRate;
  final ValueChanged<bool> onAutoplay;
  final VoidCallback onSettings;
  final VoidCallback onEpisodeList;
  final VoidCallback? onNext;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  static const _hideAfter = Duration(seconds: 4);
  bool _visible = true;
  Timer? _timer;
  final _root = FocusNode(debugLabel: 'tvPlayerRoot');
  final _play = FocusNode(debugLabel: 'tvPlayerPlayPause');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _reveal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play.requestFocus());
  }

  bool _onAnyKey(KeyEvent event) {
    if (mounted && _visible) _startTimer();
    return false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_hideAfter, () {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
        _startTimer();
        return;
      }
      setState(() => _visible = false);
      _root.requestFocus();
    });
  }

  void _reveal() {
    final hidden = !_visible;
    if (hidden) setState(() => _visible = true);
    _startTimer();
    if (hidden)
      WidgetsBinding.instance.addPostFrameCallback((_) => _play.requestFocus());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _timer?.cancel();
    _root.dispose();
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safeH = size.width * .08;
    final safeV = size.height * .05;
    final accent = Theme.of(context).colorScheme.primary;
    return PopScope(
      canPop: !_visible,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _visible) {
          setState(() => _visible = false);
          _root.requestFocus();
        }
      },
      child: Focus(
        focusNode: _root,
        onKeyEvent: (_, event) {
          if (_visible || (event is! KeyDownEvent && event is! KeyRepeatEvent))
            return KeyEventResult.ignored;
          if (_select(event.logicalKey)) widget.player.playOrPause();
          _reveal();
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          onHover: (_) => _reveal(),
          child: !_visible
              ? const SizedBox.expand()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .55),
                              Colors.black.withValues(alpha: .15),
                              Colors.black.withValues(alpha: .65),
                            ],
                            stops: const [0, .45, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: safeV,
                      left: safeH,
                      child: Row(
                        children: [
                          TvFocusable(
                            accent: accent,
                            onPressed: widget.onBack,
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TvFocusable(
                            accent: accent,
                            onPressed: () => widget.player.seek(Duration.zero),
                            child: const Icon(
                              Icons.replay_outlined,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ValueListenableBuilder<bool>(
                            valueListenable: widget.autoplay,
                            builder: (_, on, child) => TvFocusable(
                              accent: accent,
                              onPressed: () => widget.onAutoplay(!on),
                              child: AutoplaySwitch(on: on, accent: accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: safeV,
                      right: safeH,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.source.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.source.episodeLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: safeH,
                      right: safeH,
                      bottom: safeV,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              StreamBuilder<bool>(
                                stream: widget.player.stream.playing,
                                initialData: widget.player.state.playing,
                                builder: (_, snap) => TvFocusable(
                                  accent: accent,
                                  focusNode: _play,
                                  onPressed: widget.player.playOrPause,
                                  child: Icon(
                                    snap.data == true
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              _Position(player: widget.player),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TvSeekBar(
                                  player: widget.player,
                                  accent: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              _Remaining(player: widget.player),
                              if (widget.onNext != null) ...[
                                const SizedBox(width: 8),
                                TvFocusable(
                                  accent: accent,
                                  onPressed: widget.onNext,
                                  child: const Icon(
                                    Icons.skip_next,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final quality in widget.source.qualities)
                                TrackPill(
                                  accent: accent,
                                  icon: Icons.high_quality,
                                  label: quality.label,
                                  selected:
                                      quality.url == widget.currentQuality.url,
                                  onTap: () => widget.onQuality(quality),
                                ),
                              const PillDivider(),
                              _SubtitlePills(
                                player: widget.player,
                                accent: accent,
                                source: widget.source,
                              ),
                              const PillDivider(),
                              ValueListenableBuilder<double>(
                                valueListenable: widget.speed,
                                builder: (_, rate, child) => TrackPill(
                                  accent: accent,
                                  icon: Icons.speed,
                                  label: '${rate}x',
                                  selected: rate != 1,
                                  onTap: () => _speedMenu(context, rate),
                                ),
                              ),
                              const PillDivider(),
                              if (widget.source.episodes.isNotEmpty) ...[
                                TrackPill(
                                  accent: accent,
                                  icon: Icons.playlist_play,
                                  label: 'Episodes',
                                  selected: false,
                                  onTap: widget.onEpisodeList,
                                ),
                                const PillDivider(),
                              ],
                              TrackPill(
                                accent: accent,
                                icon: Icons.settings,
                                label: 'Settings',
                                selected: false,
                                onTap: widget.onSettings,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _speedMenu(BuildContext context, double current) async {
    final picked = await showDialog<double>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Playback speed'),
        children: [
          for (final speed in const [.25, .5, .75, 1.0, 1.25, 1.5, 1.75, 2.0])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, speed),
              child: Row(
                children: [
                  Expanded(child: Text('${speed}x')),
                  if (speed == current) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) widget.onRate(picked);
  }
}

bool _select(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.accent,
    required this.onPressed,
    required this.child,
    this.focusNode,
  });
  final Color accent;
  final VoidCallback? onPressed;
  final Widget child;
  final FocusNode? focusNode;
  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    canRequestFocus: widget.onPressed != null,
    onFocusChange: (value) => setState(() => focused = value),
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          _select(event.logicalKey) &&
          widget.onPressed != null) {
        widget.onPressed!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? widget.accent : Colors.black.withValues(alpha: .35),
        ),
        child: widget.child,
      ),
    ),
  );
}

class TrackPill extends StatefulWidget {
  const TrackPill({
    super.key,
    required this.accent,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Color accent;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<TrackPill> createState() => _TrackPillState();
}

class _TrackPillState extends State<TrackPill> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (v) => setState(() => focused = v),
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && _select(event.logicalKey)) {
        widget.onTap();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: focused
              ? widget.accent
              : widget.selected
              ? widget.accent.withValues(alpha: .4)
              : Colors.white.withValues(alpha: .15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.selected ? Icons.check : widget.icon,
              color: Colors.white,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class PillDivider extends StatelessWidget {
  const PillDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.white.withValues(alpha: .3),
  );
}

class AutoplaySwitch extends StatelessWidget {
  const AutoplaySwitch({super.key, required this.on, required this.accent});
  final bool on;
  final Color accent;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 28,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: on ? accent.withValues(alpha: .5) : Colors.white24,
          ),
        ),
        AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
            ),
            child: Icon(
              on ? Icons.play_arrow : Icons.pause,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ],
    ),
  );
}

class TvSeekBar extends StatefulWidget {
  const TvSeekBar({super.key, required this.player, required this.accent});
  final Player player;
  final Color accent;
  @override
  State<TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<TvSeekBar> {
  bool focused = false;
  int repeats = 0;
  LogicalKeyboardKey? direction;
  void seek(int sign, LogicalKeyboardKey key) {
    repeats = direction == key ? repeats + 1 : 0;
    direction = key;
    final step = (10 + repeats ~/ 3 * 10).clamp(10, 90);
    var target = widget.player.state.position + Duration(seconds: sign * step);
    target = clampPlayerDuration(target, widget.player.state.duration);
    widget.player.seek(target);
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (v) => setState(() => focused = v),
    onKeyEvent: (_, event) {
      final key = event.logicalKey;
      if (event is KeyUpEvent) {
        direction = null;
        repeats = 0;
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          seek(-1, key);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          seek(1, key);
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && _select(key)) {
          widget.player.playOrPause();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
    child: StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (_, snap) {
        final duration = widget.player.state.duration;
        final value = duration.inMilliseconds > 0
            ? (snap.data ?? Duration.zero).inMilliseconds /
                  duration.inMilliseconds
            : 0.0;
        return Slider(
          value: value.clamp(0, 1),
          onChanged: (fraction) => widget.player.seek(duration * fraction),
          activeColor: widget.accent,
          thumbColor: Colors.white,
        );
      },
    ),
  );
}

class _SubtitlePills extends StatelessWidget {
  const _SubtitlePills({
    required this.player,
    required this.accent,
    required this.source,
  });
  final Player player;
  final Color accent;
  final PlayerSource source;
  @override
  Widget build(BuildContext context) => StreamBuilder<Track>(
    stream: player.stream.track,
    initialData: player.state.track,
    builder: (_, selected) => StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (_, snap) {
        final tracks = [
          ...(snap.data ?? const Tracks()).subtitle.where(
            (t) => t.id != 'auto' && t.id != 'no',
          ),
          ...source.subtitleTracks.map(
            (s) =>
                SubtitleTrack.uri(s.url, title: s.label, language: s.language),
          ),
        ];
        final current = selectedSubtitleTrack(
          tracks,
          (selected.data ?? const Track()).subtitle,
        );
        return Wrap(
          spacing: 8,
          children: [
            for (final track in tracks)
              TrackPill(
                accent: accent,
                icon: Icons.subtitles,
                label: playerTrackLabel(
                  id: track.id,
                  title: track.title,
                  language: track.language,
                ),
                selected: isSubtitleTrackActive(track, current),
                onTap: () => player.setSubtitleTrack(
                  isSubtitleTrackActive(track, current)
                      ? SubtitleTrack.no()
                      : track,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _Position extends StatelessWidget {
  const _Position({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.stream.position,
    initialData: player.state.position,
    builder: (_, snap) => Text(
      formatPlayerTime(snap.data ?? Duration.zero),
      style: _timeStyle(Colors.white),
    ),
  );
}

class _Remaining extends StatelessWidget {
  const _Remaining({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.stream.position,
    initialData: player.state.position,
    builder: (_, snap) => Text(
      '-${formatPlayerTime(clampPlayerDuration(player.state.duration - (snap.data ?? Duration.zero), player.state.duration))}',
      style: _timeStyle(Colors.white70),
    ),
  );
}

TextStyle _timeStyle(Color color) => TextStyle(
  color: color,
  fontSize: 15,
  fontFamily: 'monospace',
  fontWeight: FontWeight.w600,
  fontFeatures: const [FontFeature.tabularFigures()],
);
