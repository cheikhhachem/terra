// Adapted from Mangayomi's anime_player_view.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'player_source.dart';
import 'player_logic.dart';

class PlayerSession {
  PlayerSession(this.player, this.source);

  final Player player;
  PlayerSource source;
  PlayerQuality? quality;
  double subtitleDelay = 0;
  double subtitleSpeed = 1;

  static PlayerOpenRequest openRequest(
    PlayerQuality quality,
    Duration position,
  ) => PlayerOpenRequest(
    url: quality.url,
    headers: quality.headers,
    position: position,
  );

  Future<void> open(
    PlayerQuality next, {
    Duration position = Duration.zero,
  }) async {
    quality = next;
    final request = openRequest(next, position);
    final ready = player.stream.tracks.firstWhere(_hasConcreteMediaTrack);
    await player.open(
      Media(request.url, httpHeaders: request.headers, start: request.position),
    );
    await ready.timeout(
      const Duration(seconds: 3),
      onTimeout: () => player.state.tracks,
    );
    final subtitle = preferredSourceSubtitle(source);
    if (subtitle != null) await player.setSubtitleTrack(subtitle);
    await _applySubtitleTiming();
  }

  Future<void> switchQuality(PlayerQuality next) =>
      open(next, position: player.state.position);

  Future<void> setSubtitleDelay(double milliseconds) async {
    subtitleDelay = milliseconds;
    await _applySubtitleTiming(refresh: true);
  }

  Future<void> setSubtitleSpeed(double value) async {
    subtitleSpeed = value.clamp(.1, 10);
    await _applySubtitleTiming(refresh: true);
  }

  Future<void> _applySubtitleTiming({bool refresh = false}) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('sub-delay', '${subtitleDelay / 1000}');
    await platform.setProperty('sub-speed', '$subtitleSpeed');
    if (refresh) await player.seek(player.state.position);
  }

  List<SubtitleTrack> subtitleTracks(Tracks tracks) => [
    SubtitleTrack.no(),
    ...tracks.subtitle.where((track) => track.id != 'auto' && track.id != 'no'),
    ...source.subtitleTracks.map(
      (track) => SubtitleTrack.uri(
        track.url,
        title: track.label,
        language: track.language,
      ),
    ),
  ];

  List<AudioTrack> audioTracks(Tracks tracks) => [
    ...tracks.audio.where((track) => track.id != 'auto' && track.id != 'no'),
    ...source.audioTracks.map(
      (track) => AudioTrack.uri(
        track.url,
        title: track.label,
        language: track.language,
      ),
    ),
  ];
}

bool _hasConcreteMediaTrack(Tracks tracks) =>
    tracks.video.any((track) => track.id != 'auto' && track.id != 'no') ||
    tracks.audio.any((track) => track.id != 'auto' && track.id != 'no');

SubtitleTrack? preferredSourceSubtitle(PlayerSource source) {
  if (source.subtitleTracks.isEmpty) return null;
  final subtitle = source.subtitleTracks.first;
  return SubtitleTrack.uri(
    subtitle.url,
    title: subtitle.label,
    language: subtitle.language,
  );
}

bool isSubtitleTrackActive(SubtitleTrack track, SubtitleTrack current) =>
    track.id == current.id ||
    _externalTrackMatch(
      track.id,
      track.title,
      track.language,
      track.uri,
      current.id,
      current.title,
      current.language,
      current.uri,
    );

bool isAudioTrackActive(AudioTrack track, AudioTrack current) =>
    track.id == current.id ||
    _externalTrackMatch(
      track.id,
      track.title,
      track.language,
      track.uri,
      current.id,
      current.title,
      current.language,
      current.uri,
    );

SubtitleTrack selectedSubtitleTrack(
  List<SubtitleTrack> tracks,
  SubtitleTrack current,
) {
  for (final track in tracks) {
    if (isSubtitleTrackActive(track, current)) return track;
  }
  if (current.id == 'auto') {
    return tracks.firstWhere(
      (track) => track.id != 'no',
      orElse: SubtitleTrack.no,
    );
  }
  return current;
}

AudioTrack selectedAudioTrack(List<AudioTrack> tracks, AudioTrack current) {
  for (final track in tracks) {
    if (isAudioTrackActive(track, current)) return track;
  }
  if (current.id == 'auto' && tracks.isNotEmpty) return tracks.first;
  return current;
}

bool _externalTrackMatch(
  String id,
  String? title,
  String? language,
  bool uri,
  String currentId,
  String? currentTitle,
  String? currentLanguage,
  bool currentUri,
) {
  if (!uri && !currentUri) return false;
  final label = _trackIdentity(title, language, id, uri);
  final currentLabel = _trackIdentity(
    currentTitle,
    currentLanguage,
    currentId,
    currentUri,
  );
  return label.isNotEmpty && label == currentLabel;
}

String _trackIdentity(String? title, String? language, String id, bool uri) {
  var value = title?.trim();
  if ((value == null || value.isEmpty) && uri) {
    final segments = Uri.tryParse(id)?.pathSegments ?? const [];
    value = segments.isEmpty ? id : segments.last;
  }
  value = value?.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return '${value?.toLowerCase() ?? ''}|${language?.toLowerCase() ?? ''}';
}

String playerTrackLabel({required String id, String? title, String? language}) {
  final isGenerated = RegExp(
    r'^(audio|subtitle|track)\s*\d+$',
    caseSensitive: false,
  ).hasMatch(title?.trim() ?? '');
  if (!isGenerated && title?.trim().isNotEmpty == true) return title!.trim();
  final code = language?.trim().toLowerCase();
  const names = {
    'ar': 'Arabic',
    'ara': 'Arabic',
    'de': 'German',
    'deu': 'German',
    'en': 'English',
    'eng': 'English',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fra': 'French',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'it': 'Italian',
    'ita': 'Italian',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'ru': 'Russian',
    'rus': 'Russian',
    'zh': 'Chinese',
    'zho': 'Chinese',
  };
  return names[code] ?? language?.trim() ?? title?.trim() ?? id;
}
