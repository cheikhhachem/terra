import 'dart:async';

import 'package:flutter/foundation.dart';

typedef PlayerProgressCallback =
    FutureOr<void> Function(Duration position, Duration duration);
typedef PlayerSubtitleMediaSearch =
    Future<List<PlayerSubtitleMedia>> Function(String query, bool series);
typedef PlayerSubtitleSearch =
    Future<List<PlayerSubtitleSource>> Function(
      PlayerSubtitleMedia media,
      String language,
      int season,
      int episode,
    );

enum PlayerLayout { auto, mobile, desktop, tv }

class PlayerQuality {
  const PlayerQuality({
    required this.label,
    required this.url,
    this.headers = const {},
  });

  final String label;
  final String url;
  final Map<String, String> headers;
}

class PlayerSubtitleSource {
  const PlayerSubtitleSource({
    required this.label,
    required this.url,
    this.language,
    this.resolveUrl,
  });

  final String label;
  final String url;
  final String? language;
  final AsyncValueGetter<String>? resolveUrl;
}

class PlayerSubtitleMedia {
  const PlayerSubtitleMedia({
    required this.imdbId,
    required this.title,
    required this.series,
    this.year,
    this.posterUrl,
  });

  final String imdbId;
  final String title;
  final bool series;
  final String? year;
  final String? posterUrl;
}

class PlayerAudioSource {
  const PlayerAudioSource({
    required this.label,
    required this.url,
    this.language,
  });

  final String label;
  final String url;
  final String? language;
}

class PlayerChapterMark {
  const PlayerChapterMark({required this.label, required this.position});

  final String label;
  final Duration position;
}

class PlayerSkipSegment {
  const PlayerSkipSegment({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final Duration start;
  final Duration end;
}

class PlayerCustomAction {
  const PlayerCustomAction({
    required this.label,
    required this.onPressed,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
}

class PlayerEpisodeEntry {
  const PlayerEpisodeEntry({
    required this.id,
    required this.label,
    required this.season,
    required this.selected,
    required this.load,
  });

  final String id;
  final String label;
  final int season;
  final bool selected;
  final AsyncValueGetter<PlayerSource> load;
}

class PlayerSource {
  const PlayerSource({
    required this.title,
    required this.episodeLabel,
    required this.resumeKey,
    required this.qualities,
    this.subtitleTracks = const [],
    this.audioTracks = const [],
    this.chapterMarks = const [],
    this.skipSegments = const [],
    this.customActions = const [],
    this.skipIntro = const Duration(seconds: 85),
    this.onNext,
    this.onPrevious,
    this.episodes = const [],
    this.subtitleSearchQuery,
    this.subtitleSearchSeries = true,
    this.subtitleSearchSeason = 1,
    this.subtitleSearchEpisode = 1,
    this.subtitleSearchLanguage = 'eng',
    this.onSearchSubtitleMedia,
    this.onSearchSubtitles,
    this.onProgress,
    this.layout = PlayerLayout.auto,
  }) : assert(qualities.length > 0);

  final String title;
  final String episodeLabel;
  final String resumeKey;
  final List<PlayerQuality> qualities;
  final List<PlayerSubtitleSource> subtitleTracks;
  final List<PlayerAudioSource> audioTracks;
  final List<PlayerChapterMark> chapterMarks;
  final List<PlayerSkipSegment> skipSegments;
  final List<PlayerCustomAction> customActions;
  final Duration skipIntro;
  final AsyncValueGetter<PlayerSource>? onNext;
  final AsyncValueGetter<PlayerSource>? onPrevious;
  final List<PlayerEpisodeEntry> episodes;
  final String? subtitleSearchQuery;
  final bool subtitleSearchSeries;
  final int subtitleSearchSeason;
  final int subtitleSearchEpisode;
  final String subtitleSearchLanguage;
  final PlayerSubtitleMediaSearch? onSearchSubtitleMedia;
  final PlayerSubtitleSearch? onSearchSubtitles;
  final PlayerProgressCallback? onProgress;
  final PlayerLayout layout;
}
