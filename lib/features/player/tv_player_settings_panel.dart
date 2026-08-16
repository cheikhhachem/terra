// Adapted from Mangayomi's tv_player_settings_panel.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures, unnecessary_underscores
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'player_session.dart';
import 'player_source.dart';

class TvPlayerSettingsPanel extends StatefulWidget {
  const TvPlayerSettingsPanel({
    super.key,
    required this.session,
    required this.speed,
    required this.onSpeed,
    required this.onQuality,
    required this.headerFocusNode,
    required this.onExitLeft,
    required this.onClose,
  });

  final PlayerSession session;
  final ValueListenable<double> speed;
  final ValueChanged<double> onSpeed;
  final ValueChanged<PlayerQuality> onQuality;
  final FocusNode headerFocusNode;
  final VoidCallback onExitLeft;
  final VoidCallback onClose;

  @override
  State<TvPlayerSettingsPanel> createState() => _TvPlayerSettingsPanelState();
}

class _TvPlayerSettingsPanelState extends State<TvPlayerSettingsPanel> {
  String? open;
  static const speeds = [.25, .5, .75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const decoders = [
    'auto',
    'auto-copy',
    'mediacodec',
    'mediacodec-copy',
    'videotoolbox',
    'd3d11va',
    'nvdec',
    'no',
  ];
  static const shaders = [
    ('Anime4K: Mode A (Fast)', 'set_anime_a'),
    ('Anime4K: Mode B (Fast)', 'set_anime_b'),
    ('Anime4K: Mode C (Fast)', 'set_anime_c'),
    ('AMD FSR', 'set_fsr'),
    ('Luma Upscaling', 'set_luma'),
    ('Off (clear shaders)', 'clear_anime'),
  ];

  Player get player => widget.session.player;
  NativePlayer? get native =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  void back() {
    if (open != null)
      setState(() => open = null);
    else
      widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final width = (MediaQuery.sizeOf(context).width * .26).clamp(300.0, 380.0);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => back(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onExitLeft();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: width,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      focusNode: widget.headerFocusNode,
                      onPressed: back,
                      icon: Icon(open == null ? Icons.close : Icons.arrow_back),
                    ),
                    Text(
                      open == null ? 'Settings' : _title(open!),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: open == null ? _categories(accent) : _page(accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title(String key) => switch (key) {
    'speed' => 'Playback speed',
    'quality' => 'Quality',
    'subtitles' => 'Subtitles',
    'audio' => 'Audio',
    'shaders' => 'Shaders',
    'decoder' => 'Decoder',
    'stats' => 'Stats for nerds',
    _ => 'Settings',
  };

  Widget _categories(Color accent) => ListView(
    children: [
      for (final item in const [
        ('speed', Icons.speed, 'Playback speed'),
        ('quality', Icons.high_quality, 'Quality'),
        ('subtitles', Icons.subtitles, 'Subtitles'),
        ('audio', Icons.audiotrack, 'Audio'),
        ('shaders', Icons.auto_awesome, 'Shaders'),
        ('decoder', Icons.memory, 'Decoder'),
        ('stats', Icons.insights, 'Stats for nerds'),
      ])
        _NavRow(
          accent: accent,
          icon: item.$2,
          label: item.$3,
          onTap: () => setState(() => open = item.$1),
        ),
    ],
  );

  Widget _page(Color accent) => switch (open) {
    'speed' => ValueListenableBuilder<double>(
      valueListenable: widget.speed,
      builder: (_, rate, __) => _options(accent, [
        for (final speed in speeds)
          (
            label: '${speed}x',
            selected: speed == rate,
            action: () => widget.onSpeed(speed),
          ),
      ]),
    ),
    'quality' => _options(accent, [
      for (final quality in widget.session.source.qualities)
        (
          label: quality.label,
          selected: quality.url == widget.session.quality?.url,
          action: () => widget.onQuality(quality),
        ),
    ]),
    'subtitles' => StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (_, selected) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (_, snap) {
          final tracks = widget.session.subtitleTracks(
            snap.data ?? player.state.tracks,
          );
          final current = selectedSubtitleTrack(
            tracks,
            (selected.data ?? const Track()).subtitle,
          );
          return _options(accent, [
            for (final track in tracks)
              (
                label: track.id == 'no'
                    ? 'Off'
                    : playerTrackLabel(
                        id: track.id,
                        title: track.title,
                        language: track.language,
                      ),
                selected: isSubtitleTrackActive(track, current),
                action: () => player.setSubtitleTrack(track),
              ),
          ]);
        },
      ),
    ),
    'audio' => StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (_, selected) => StreamBuilder<Tracks>(
        stream: player.stream.tracks,
        initialData: player.state.tracks,
        builder: (_, snap) {
          final tracks = widget.session.audioTracks(
            snap.data ?? player.state.tracks,
          );
          final current = selectedAudioTrack(
            tracks,
            (selected.data ?? const Track()).audio,
          );
          return _options(accent, [
            for (final track in tracks)
              (
                label: playerTrackLabel(
                  id: track.id,
                  title: track.title,
                  language: track.language,
                ),
                selected: isAudioTrackActive(track, current),
                action: () => player.setAudioTrack(track),
              ),
          ]);
        },
      ),
    ),
    'shaders' => _options(accent, [
      for (final shader in shaders)
        (
          label: shader.$1,
          selected: false,
          action: () => native?.command(['script-message', shader.$2]),
        ),
    ]),
    'decoder' => _options(accent, [
      for (final decoder in decoders)
        (
          label: decoder,
          selected: false,
          action: () => native?.setProperty('hwdec', decoder),
        ),
    ]),
    'stats' => _options(accent, [
      for (final stat in const [
        ('Toggle overlay', 'stats/display-stats-toggle'),
        ('General', 'stats/display-page-1'),
        ('Frame timings', 'stats/display-page-2'),
        ('Input cache', 'stats/display-page-3'),
        ('Active filters', 'stats/display-page-4'),
        ('Log', 'stats/display-page-5'),
      ])
        (
          label: stat.$1,
          selected: false,
          action: () => native?.command(['script-binding', stat.$2]),
        ),
    ]),
    _ => const SizedBox.shrink(),
  };

  Widget _options(
    Color accent,
    List<({String label, bool selected, VoidCallback action})> values,
  ) => ListView(
    children: [
      for (final value in values)
        _OptionRow(
          accent: accent,
          label: value.label,
          selected: value.selected,
          onTap: value.action,
        ),
    ],
  );
}

class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.accent,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Color accent;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: focused ? widget.accent.withValues(alpha: .18) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: widget.accent),
            const SizedBox(width: 14),
            Expanded(child: Text(widget.label)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Color accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? widget.accent.withValues(alpha: .18) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: widget.selected ? FontWeight.bold : null,
                  color: widget.selected ? widget.accent : null,
                ),
              ),
            ),
            if (widget.selected) Icon(Icons.check, color: widget.accent),
          ],
        ),
      ),
    ),
  );
}

bool _select(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

class TvVideoFocusFrame extends StatefulWidget {
  const TvVideoFocusFrame({
    super.key,
    required this.player,
    required this.focusNode,
    required this.onExitRight,
    required this.child,
  });
  final Player player;
  final FocusNode focusNode;
  final VoidCallback onExitRight;
  final Widget child;
  @override
  State<TvVideoFocusFrame> createState() => _TvVideoFocusFrameState();
}

class _TvVideoFocusFrameState extends State<TvVideoFocusFrame> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    onFocusChange: (v) => setState(() => focused = v),
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.onExitRight();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent && _select(event.logicalKey)) {
        widget.player.playOrPause();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: widget.child,
      ),
    ),
  );
}
