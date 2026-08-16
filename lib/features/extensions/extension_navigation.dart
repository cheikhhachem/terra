import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_models.dart';
import '../library/library_repository.dart';
import '../downloads/download_repository.dart';
import '../player/player_page.dart';
import '../player/player_source.dart';
import '../settings/app_settings.dart';
import '../subtitles/open_subtitles.dart';
import '../subtitles/subdl.dart';
import '../../widgets/episode_operation_overlay.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'extension_detail_repository.dart';
import 'sora_extension_service.dart';

LibraryMedia libraryMediaFor(
  InstalledSoraModule module,
  SoraSearchResult result, {
  DateTime? addedAt,
}) => LibraryMedia(
  id: '${module.id}:${result.href}',
  moduleId: module.id,
  sourceName: module.metadata.sourceName,
  title: result.title,
  imageUrl: result.imageUrl,
  detailHref: result.href,
  addedAt: addedAt ?? DateTime.now(),
);

Future<void> resumeExtensionEntry({
  required BuildContext context,
  required InstalledSoraModule module,
  required ContinueWatchingEntry entry,
  required ExtensionService service,
  required ExtensionDetailRepository details,
  required LibraryRepository library,
  required DownloadRepository downloads,
}) async {
  final result = SoraSearchResult(
    title: entry.media.title,
    imageUrl: entry.media.imageUrl,
    href: entry.media.detailHref,
  );
  final source = await runEpisodeOperation(context, () async {
    var value = await details.read(module, result.href);
    if (value == null) {
      value = await details.refresh(module, result.href);
    } else {
      unawaited(details.refresh(module, result.href).catchError((_) => value!));
    }
    final index = value.episodes.indexWhere(
      (episode) => episode.href == entry.episodeHref,
    );
    if (index < 0) {
      throw StateError(
        'The saved episode is no longer available from this source.',
      );
    }
    return _extensionPlayerSource(
      module: module,
      result: result,
      episodes: value.episodes,
      index: index,
      service: service,
      library: library,
      details: value.details,
    );
  });
  if (source == null || !context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PlayerPage(source: source)));
}

Future<void> openExtensionEpisode({
  required BuildContext context,
  required InstalledSoraModule module,
  required SoraSearchResult result,
  required List<SoraEpisode> episodes,
  required int index,
  required ExtensionService service,
  required LibraryRepository library,
  SoraDetails? details,
  required DownloadRepository downloads,
}) async {
  if (index < 0 || index >= episodes.length) return;
  late Future<PlayerSource> Function(int index) loadSource;
  loadSource = (nextIndex) => _extensionPlayerSource(
    module: module,
    result: result,
    episodes: episodes,
    index: nextIndex,
    service: service,
    library: library,
    details: details,
  );
  final source = await runEpisodeOperation(context, () => loadSource(index));
  if (source == null) return;
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PlayerPage(source: source)));
}

Future<PlayerSource> _extensionPlayerSource({
  required InstalledSoraModule module,
  required SoraSearchResult result,
  required List<SoraEpisode> episodes,
  required int index,
  required ExtensionService service,
  required LibraryRepository library,
  SoraDetails? details,
}) async {
  final episode = episodes[index];
  final streams = await service.streams(module, episode);
  final media = libraryMediaFor(module, result);
  final mediaType = result.mediaType ?? details?.mediaType;
  final series =
      mediaType != 'movie' && (mediaType == 'series' || episodes.length > 1);
  final subtitleLanguage =
      await SharedPreferencesAsync().getString(
        AppSettings.subtitleLanguageKey,
      ) ??
      'eng';
  late Future<PlayerSource> Function(int index) loadSource;
  loadSource = (nextIndex) => _extensionPlayerSource(
    module: module,
    result: result,
    episodes: episodes,
    index: nextIndex,
    service: service,
    library: library,
    details: details,
  );
  return service.toPlayerSource(
    module: module,
    result: result,
    episode: episode,
    sources: streams,
    episodes: [
      for (final item in episodes.indexed)
        PlayerEpisodeEntry(
          id: '${module.id}:${item.$2.href}',
          label: item.$2.label,
          season: item.$2.season ?? 1,
          selected: item.$1 == index,
          load: () => loadSource(item.$1),
        ),
    ],
    onNext: index + 1 < episodes.length ? () => loadSource(index + 1) : null,
    onPrevious: index > 0 ? () => loadSource(index - 1) : null,
    subtitleSearchQuery: result.title,
    subtitleSearchSeries: series,
    subtitleSearchSeason: episode.season ?? 1,
    subtitleSearchEpisode: _subtitleEpisodeNumber(episode),
    subtitleSearchLanguage: subtitleLanguage,
    onSearchSubtitleMedia: (query, selectedSeries) async {
      return const OpenSubtitlesClient().searchMedia(
        query: query,
        series: selectedSeries,
      );
    },
    onSearchSubtitles: (media, language, season, selectedEpisode) async {
      final key =
          await const FlutterSecureStorage().read(
            key: AppSettings.subdlApiKeyName,
          ) ??
          '';
      final results = await Future.wait([
        const OpenSubtitlesClient()
            .search(
              imdbId: media.imdbId,
              series: media.series,
              language: language,
              season: season,
              episode: selectedEpisode,
            )
            .catchError((_) => <PlayerSubtitleSource>[]),
        if (key.isNotEmpty)
          const SubdlClient()
              .search(
                apiKey: key,
                media: media,
                language: language,
                season: season,
                episode: selectedEpisode,
              )
              .catchError((_) => <PlayerSubtitleSource>[]),
      ]);
      return results.expand((tracks) => tracks).toList();
    },
    onProgress: (position, duration) => library.updateWatchingProgress(
      media: media,
      episodeHref: episode.href,
      episodeLabel: episode.label,
      episodeNumber: episode.number,
      season: episode.season ?? 1,
      position: position,
      duration: duration,
    ),
  );
}

int _subtitleEpisodeNumber(SoraEpisode episode) {
  for (final pattern in [
    RegExp(r'\b(?:episode|ep|e)\s*0*(\d+)\b', caseSensitive: false),
    RegExp(r'\bS\d+E0*(\d+)\b', caseSensitive: false),
  ]) {
    final match = pattern.firstMatch(episode.label);
    if (match != null) return int.parse(match.group(1)!);
  }
  return episode.number.round();
}
