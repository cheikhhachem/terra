// Adapted from Mangayomi's anime_player_view.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:window_manager/window_manager.dart';

import 'aniskip_countdown_button.dart';
import 'player_controls.dart';
import 'player_logic.dart';
import 'player_preferences.dart';
import 'player_session.dart';
import 'player_settings.dart';
import 'player_source.dart';
import 'tv_player_controls.dart';
import 'tv_player_settings_panel.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.source, this.preferences});
  final PlayerSource source;
  final PlayerPreferences? preferences;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final Player _player = Player(
    configuration: PlayerConfiguration(
      libass: false,
      options: const {'audio-pitch-correction': 'yes', 'volume-max': '130'},
    ),
  );
  late final VideoController _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      hwdec: Platform.isAndroid ? 'auto-safe' : 'auto',
      enableHardwareAcceleration: !Platform.isMacOS,
      vo: Platform.isAndroid ? 'gpu' : 'libmpv',
    ),
  );
  late PlayerSource _source = widget.source;
  late final PlayerSession _session = PlayerSession(_player, _source);
  late final PlayerPreferences _preferences =
      widget.preferences ?? PlayerPreferences();
  final _videoKey = GlobalKey<VideoState>();
  final _speed = ValueNotifier(1.0);
  final _autoplay = ValueNotifier(true);
  final _reveal = ValueNotifier(0);
  double _subtitleSize = 36;
  double _subtitleBackgroundOpacity = .5;
  final _tvVideoFocus = FocusNode(debugLabel: 'tvVideoFrame');
  final _tvPanelFocus = FocusNode(debugLabel: 'tvPanelHeader');
  final _subscriptions = <StreamSubscription<dynamic>>[];
  PlayerQuality? _quality;
  PlayerSkipSegment? _skipSegment;
  Duration _seekIncrement = const Duration(seconds: 10);
  Duration _position = Duration.zero;
  Duration _lastSaved = Duration.zero;
  Duration? _lastProgressReported;
  Duration? _pendingResumePosition;
  DateTime? _resumeGuardUntil;
  bool _resumeEnabled = true;
  bool _ready = false;
  bool _fullscreen = false;
  bool _autoSkip = false;
  bool _tvSettingsOpen = false;
  bool _switchingEpisode = false;
  bool _disposed = false;
  BoxFit _fit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    _quality = _source.qualities.first;
    _resumeEnabled = await _preferences.resumeEnabled;
    if (_disposed) return;
    _seekIncrement = await _preferences.seekIncrement;
    if (_disposed) return;
    _autoplay.value = await _preferences.autoplay;
    if (_disposed) return;
    _autoSkip = await _preferences.autoSkip;
    if (_disposed) return;
    _subtitleSize = await _preferences.subtitleSize;
    if (_disposed) return;
    _subtitleBackgroundOpacity = await _preferences.subtitleBackgroundOpacity;
    if (_disposed) return;
    _fit = _fitFromName(await _preferences.fit);
    if (_disposed) return;
    final rate = await _preferences.defaultRate;
    if (_disposed) return;
    await _setRate(rate, persist: false);
    if (_disposed) return;
    final resumePosition = _resumeEnabled
        ? await _preferences.resumePosition(_source.resumeKey) ?? Duration.zero
        : Duration.zero;
    _pendingResumePosition = resumePosition > const Duration(seconds: 5)
        ? resumePosition
        : null;
    _resumeGuardUntil = _pendingResumePosition == null
        ? null
        : DateTime.now().add(const Duration(seconds: 5));
    _subscriptions.add(_player.stream.position.listen(_onPosition));
    await _session.open(_quality!, position: resumePosition);
    if (_disposed) return;
    _subscriptions.addAll([
      _player.stream.completed.listen((completed) {
        if (completed && _autoplay.value) _switchEpisode(_source.onNext);
      }),
    ]);
    if (mounted) {
      setState(() => _ready = true);
      if (!kIsWeb && Platform.isAndroid) await _setFullscreen(true);
    }
  }

  void _onPosition(Duration position) {
    final pending = _pendingResumePosition;
    if (pending != null) {
      if (DateTime.now().isAfter(_resumeGuardUntil!)) {
        _pendingResumePosition = null;
        _resumeGuardUntil = null;
      } else if (position < const Duration(seconds: 1)) {
        unawaited(_player.seek(pending));
        return;
      }
    }
    _position = position;
    final segment = _source.skipSegments.cast<PlayerSkipSegment?>().firstWhere(
      (segment) =>
          segment != null &&
          position >= segment.start &&
          position < segment.end,
      orElse: () => null,
    );
    if (segment != _skipSegment && mounted)
      setState(() => _skipSegment = segment);
    if (_resumeEnabled &&
        (position - _lastSaved).abs() >= const Duration(seconds: 10)) {
      _savePosition();
    }
    _reportProgress();
  }

  Future<void> _changeQuality(PlayerQuality quality) async {
    if (quality.url == _quality?.url) return;
    await _savePosition();
    if (_disposed) return;
    _pendingResumePosition = _position > const Duration(seconds: 5)
        ? _position
        : null;
    _resumeGuardUntil = _pendingResumePosition == null
        ? null
        : DateTime.now().add(const Duration(seconds: 5));
    setState(() => _quality = quality);
    await _session.switchQuality(quality);
  }

  Future<void> _setRate(double rate, {bool persist = true}) async {
    await _player.setRate(rate);
    if (_disposed) return;
    _speed.value = rate;
    if (persist) await _preferences.setDefaultRate(rate);
  }

  Future<void> _setAutoplay(bool value) async {
    if (_disposed) return;
    _autoplay.value = value;
    await _preferences.setAutoplay(value);
  }

  Future<void> _savePosition() async {
    if (!_resumeEnabled) return;
    _lastSaved = _position;
    await _preferences.saveResumePosition(_source.resumeKey, _position);
  }

  void _reportProgress({bool force = false}) {
    final callback = _source.onProgress;
    final duration = _player.state.duration;
    if (callback == null || duration <= Duration.zero) return;
    final previous = _lastProgressReported;
    if (previous == _position ||
        (!force &&
            previous != null &&
            (_position - previous).abs() < const Duration(seconds: 15))) {
      return;
    }
    _lastProgressReported = _position;
    final position = _position;
    unawaited(
      Future<void>(() async {
        try {
          await callback(position, duration);
        } catch (_) {}
      }),
    );
  }

  Future<void> _setFullscreen(bool value) async {
    if (_disposed) return;
    _fullscreen = value;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.setFullScreen(_fullscreen);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
    if (!_disposed && mounted) setState(() {});
  }

  Future<void> _toggleFullscreen() => _setFullscreen(!_fullscreen);

  Future<void> _switchEpisode(AsyncValueGetter<PlayerSource>? load) async {
    if (load == null || _switchingEpisode) return;
    _switchingEpisode = true;
    try {
      await _savePosition();
      _reportProgress(force: true);
      final source = await load();
      if (!mounted) return;
      final quality = source.qualities.first;
      final position = _resumeEnabled
          ? await _preferences.resumePosition(source.resumeKey) ?? Duration.zero
          : Duration.zero;
      if (_disposed || !mounted) return;
      _source = source;
      _session.source = source;
      _quality = quality;
      _position = position;
      _pendingResumePosition = position > const Duration(seconds: 5)
          ? position
          : null;
      _resumeGuardUntil = _pendingResumePosition == null
          ? null
          : DateTime.now().add(const Duration(seconds: 5));
      _lastSaved = position;
      _lastProgressReported = null;
      _skipSegment = null;
      setState(() {});
      await _session.open(quality, position: position);
      if (_fullscreen) await _setFullscreen(true);
    } finally {
      _switchingEpisode = false;
    }
  }

  Future<void> _cycleFit() async {
    const fits = [
      BoxFit.contain,
      BoxFit.cover,
      BoxFit.fill,
      BoxFit.fitHeight,
      BoxFit.fitWidth,
      BoxFit.scaleDown,
      BoxFit.none,
    ];
    _fit = fits[(fits.indexOf(_fit) + 1) % fits.length];
    _videoKey.currentState?.update(fit: _fit);
    await _preferences.setFit(_fit.name);
    if (mounted) {
      showFToast(
        context: context,
        title: Text('Fit: ${_fitLabel(_fit)}'),
        alignment: .topRight,
        duration: const Duration(seconds: 1),
      );
      setState(() {});
    }
  }

  Future<void> _showSettings() => showPlayerSettings(
    context,
    session: _session,
    onQuality: _changeQuality,
    onRate: _setRate,
    onFit: _cycleFit,
    subtitleSize: _subtitleSize,
    subtitleBackgroundOpacity: _subtitleBackgroundOpacity,
    onSubtitleSize: (value) {
      setState(() => _subtitleSize = value);
      _preferences.setSubtitleSize(value);
    },
    onSubtitleBackgroundOpacity: (value) {
      setState(() => _subtitleBackgroundOpacity = value);
      _preferences.setSubtitleBackgroundOpacity(value);
    },
  );

  Future<void> _showEpisodeList() async {
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    final selected = await showFSheet<PlayerEpisodeEntry>(
      context: context,
      side: desktop ? .rtl : .btt,
      mainAxisMaxRatio: desktop ? .4 : .75,
      useSafeArea: true,
      builder: (sheetContext) => Material(
        color: Theme.of(sheetContext).colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Episodes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final season in _groupPlayerEpisodes(
                    _source.episodes,
                  ).entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                      child: Text(
                        'Season ${season.key}',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    for (final episode in season.value)
                      ListTile(
                        key: ValueKey(episode.id),
                        selected: episode.selected,
                        leading: Icon(
                          episode.selected
                              ? Icons.play_circle_filled
                              : Icons.play_circle_outline,
                        ),
                        title: Text(episode.label),
                        trailing: episode.selected
                            ? const Icon(Icons.check)
                            : null,
                        onTap: episode.selected
                            ? () => Navigator.pop(sheetContext)
                            : () => Navigator.pop(sheetContext, episode),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _switchEpisode(selected.load);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _savePosition();
      _reportProgress(force: true);
    } else if (state == AppLifecycleState.resumed && _fullscreen) {
      _setFullscreen(true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _savePosition();
    _reportProgress(force: true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      ScreenBrightness.instance.resetApplicationScreenBrightness().ignore();
    }
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _speed.dispose();
    _autoplay.dispose();
    _reveal.dispose();
    _tvVideoFocus.dispose();
    _tvPanelFocus.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layoutFor(context);
    final player = Stack(
      fit: StackFit.expand,
      children: [
        Video(
          key: _videoKey,
          controller: _video,
          fit: _tvSettingsOpen ? BoxFit.contain : _fit,
          controls: (_) => _ready ? _controls(layout) : const SizedBox.shrink(),
          resumeUponEnteringForegroundMode: true,
          subtitleViewConfiguration: SubtitleViewConfiguration(
            style: TextStyle(
              height: 1.4,
              fontSize: _subtitleSize,
              color: Colors.white,
              backgroundColor: Colors.black.withValues(
                alpha: _subtitleBackgroundOpacity,
              ),
            ),
          ),
        ),
        if (_skipSegment != null)
          Positioned(
            right: 0,
            bottom: 80,
            child: AniSkipCountdownButton(
              key: ValueKey(_skipSegment),
              segment: _skipSegment!,
              player: _player,
              autoSkip: _autoSkip,
            ),
          ),
      ],
    );
    final body = layout == PlayerLayout.tv && _tvSettingsOpen
        ? ColoredBox(
            color: Colors.black,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TvVideoFocusFrame(
                      player: _player,
                      focusNode: _tvVideoFocus,
                      onExitRight: () => _tvPanelFocus.requestFocus(),
                      child: player,
                    ),
                  ),
                ),
                TvPlayerSettingsPanel(
                  session: _session,
                  speed: _speed,
                  onSpeed: _setRate,
                  onQuality: _changeQuality,
                  headerFocusNode: _tvPanelFocus,
                  onExitLeft: () => _tvVideoFocus.requestFocus(),
                  onClose: () => setState(() => _tvSettingsOpen = false),
                ),
              ],
            ),
          )
        : player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: !_fullscreen,
        onPopInvokedWithResult: (popped, _) {
          if (!popped && _fullscreen) _toggleFullscreen();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                _player.playOrPause,
            const SingleActivator(LogicalKeyboardKey.mediaPlay): _player.play,
            const SingleActivator(LogicalKeyboardKey.mediaPause): _player.pause,
            const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(-10),
            const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(10),
            const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
                _switchEpisode(_source.onNext),
            const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
                _switchEpisode(_source.onPrevious),
          },
          child: MouseRegion(
            onEnter: (_) => _reveal.value++,
            onHover: (_) => _reveal.value++,
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.mouse) _reveal.value++;
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: _onPlayerKey,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(PlayerLayout layout) {
    if (layout == PlayerLayout.tv) {
      return TvPlayerControls(
        player: _player,
        source: _source,
        currentQuality: _quality!,
        speed: _speed,
        autoplay: _autoplay,
        onBack: () => Navigator.pop(context),
        onQuality: _changeQuality,
        onRate: _setRate,
        onAutoplay: _setAutoplay,
        onSettings: () {
          setState(() => _tvSettingsOpen = true);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tvPanelFocus.requestFocus(),
          );
        },
        onEpisodeList: _showEpisodeList,
        onNext: _source.onNext == null
            ? null
            : () => _switchEpisode(_source.onNext),
      );
    }
    return PlayerControls(
      controller: _video,
      source: _source,
      seekIncrement: _seekIncrement,
      onBack: () => Navigator.pop(context),
      onSettings: _showSettings,
      onFullscreen: _toggleFullscreen,
      onFit: _cycleFit,
      onEpisodeList: _showEpisodeList,
      onNext: _source.onNext == null
          ? null
          : () => _switchEpisode(_source.onNext),
      onPrevious: _source.onPrevious == null
          ? null
          : () => _switchEpisode(_source.onPrevious),
      autoplay: _autoplay,
      onAutoplay: _setAutoplay,
      desktop: layout == PlayerLayout.desktop,
    );
  }

  PlayerLayout _layoutFor(BuildContext context) {
    if (_source.layout != PlayerLayout.auto) return _source.layout;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      return PlayerLayout.desktop;
    return PlayerLayout.mobile;
  }

  void _seekBy(int seconds) {
    var target = _player.state.position + Duration(seconds: seconds);
    target = clampPlayerDuration(target, _player.state.duration);
    _player.seek(target);
  }

  KeyEventResult _onPlayerKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA)
        _reveal.value++;
    }
    return KeyEventResult.ignored;
  }
}

BoxFit _fitFromName(String name) => BoxFit.values.firstWhere(
  (fit) => fit.name == name,
  orElse: () => BoxFit.contain,
);

String _fitLabel(BoxFit fit) => switch (fit) {
  BoxFit.contain => 'Contain',
  BoxFit.cover => 'Cover',
  BoxFit.fill => 'Fill',
  BoxFit.fitHeight => 'Fit height',
  BoxFit.fitWidth => 'Fit width',
  BoxFit.scaleDown => 'Scale down',
  BoxFit.none => 'None',
};

Map<int, List<PlayerEpisodeEntry>> _groupPlayerEpisodes(
  List<PlayerEpisodeEntry> episodes,
) {
  final grouped = <int, List<PlayerEpisodeEntry>>{};
  for (final episode in episodes) {
    grouped.putIfAbsent(episode.season, () => []).add(episode);
  }
  return grouped;
}
