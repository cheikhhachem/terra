// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../player/player_source.dart';
import '../reading/reading_models.dart';
import 'extension_facets.dart';
import 'extension_manager.dart';
import 'models.dart';
import 'sora_network.dart';
import 'sora_runtime.dart';

class ExtensionService {
  ExtensionService(this.manager, {SoraRuntime? runtime})
    : _runtimeOverride = runtime;
  final ExtensionManager manager;
  final SoraRuntime? _runtimeOverride;
  final Map<String, SoraRuntime> _runtimes = {};

  void dispose() {
    _runtimeOverride?.dispose();
    for (final runtime in _runtimes.values) runtime.dispose();
  }

  Future<List<SoraSearchResult>> search(
    InstalledSoraModule module,
    String keyword,
  ) async {
    if (module.metadata.kind == ExtensionKind.mangayomi) {
      final value = await _invoke(module, '__terraMangayomiSearch', keyword);
      return _listField(value, 'list')
          .map(SoraSearchResult.fromJson)
          .where((item) => item.title.isNotEmpty && item.href.isNotEmpty)
          .toList();
    }
    final argument = module.metadata.asyncJS
        ? keyword
        : await _fetch(
            module.metadata.searchBaseUrl.replaceAll(
              '%s',
              Uri.encodeQueryComponent(keyword),
            ),
          );
    final value = await _invoke(module, 'searchResults', argument);
    return soraList(value)
        .map(SoraSearchResult.fromJson)
        .where((item) => item.title.isNotEmpty && item.href.isNotEmpty)
        .toList();
  }

  Future<(SoraDetails, List<SoraEpisode>)> details(
    InstalledSoraModule module,
    String url,
  ) async {
    if (module.metadata.kind == ExtensionKind.mangayomi) {
      final value = await _invoke(module, '__terraMangayomiDetail', url);
      final decoded = decodeSoraValue(value);
      final json = decoded is Map ? decoded : const <Object?, Object?>{};
      final episodes = _listField(json['episodes'], '').indexed
          .map((item) => SoraEpisode.fromJson(item.$2, item.$1))
          .where((item) => item.href.isNotEmpty)
          .toList();
      return (
        SoraDetails.fromJson(json),
        groupSoraEpisodesBySeason(
          episodes,
        ).values.expand((items) => items).toList(),
      );
    }
    final argument = module.metadata.asyncJS ? url : await _fetch(url);
    final values = await Future.wait([
      _invoke(module, 'extractDetails', argument),
      _invoke(module, 'extractEpisodes', argument),
    ]);
    final details = soraList(values[0]);
    final episodes = soraList(values[1]).indexed
        .map((item) => SoraEpisode.fromJson(item.$2, item.$1))
        .where((item) => item.href.isNotEmpty)
        .toList();
    return (
      details.isEmpty
          ? const SoraDetails()
          : SoraDetails.fromJson(details.first),
      groupSoraEpisodesBySeason(
        episodes,
      ).values.expand((items) => items).toList(),
    );
  }

  Future<SoraStreams> streams(
    InstalledSoraModule module,
    SoraEpisode episode,
  ) async {
    if (module.metadata.kind == ExtensionKind.mangayomi) {
      return SoraStreams.fromValue(
        await _invoke(module, '__terraMangayomiVideos', episode.href),
      );
    }
    final argument = module.metadata.asyncJS
        ? episode.href
        : await _fetch(episode.href);
    return SoraStreams.fromValue(
      await _invoke(module, 'extractStreamUrl', argument),
    );
  }

  ReadMediaKind readKind(InstalledSoraModule module) {
    final types = extensionMediaTypes(module.metadata.type);
    return module.metadata.novel ||
            types.any(
              {'Novel', 'Light Novel', 'Web Novel', 'Book', 'eBook'}.contains,
            )
        ? ReadMediaKind.novel
        : ReadMediaKind.manga;
  }

  Future<List<ReadSearchResult>> searchRead(
    InstalledSoraModule module,
    String keyword,
  ) async {
    final value = module.metadata.kind == ExtensionKind.mangayomi
        ? await _invoke(module, '__terraMangayomiSearch', keyword)
        : await _invoke(
            module,
            'searchResults',
            module.metadata.asyncJS
                ? keyword
                : await _fetch(
                    module.metadata.searchBaseUrl.replaceAll(
                      '%s',
                      Uri.encodeQueryComponent(keyword),
                    ),
                  ),
          );
    final values = module.metadata.kind == ExtensionKind.mangayomi
        ? _listField(value, 'list')
        : soraList(value);
    return values
        .map(ReadSearchResult.fromJson)
        .where((item) => item.title.isNotEmpty && item.href.isNotEmpty)
        .toList();
  }

  Future<ReadDetails> readDetails(
    InstalledSoraModule module,
    String url,
  ) async {
    if (module.metadata.kind == ExtensionKind.mangayomi) {
      final value = decodeReadValue(
        await _invoke(module, '__terraMangayomiDetail', url),
      );
      final json = value is Map ? value : const <Object?, Object?>{};
      final chapters = ReadChapter.listFrom(
        json['chapters'] ?? json['episodes'],
      );
      return ReadDetails.fromJson(json, chapters);
    }
    final argument = module.metadata.asyncJS ? url : await _fetch(url);
    final values = await Future.wait([
      _invoke(module, 'extractDetails', argument),
      _invoke(module, 'extractChapters', argument),
    ]);
    final rawDetails = soraList(values[0]);
    return ReadDetails.fromJson(
      rawDetails.isEmpty ? decodeReadValue(values[0]) : rawDetails.first,
      ReadChapter.listFrom(decodeReadValue(values[1])),
    );
  }

  Future<List<ReadPage>> readPages(
    InstalledSoraModule module,
    ReadChapter chapter,
  ) async {
    if (readKind(module) == ReadMediaKind.novel) return const [];
    if (module.metadata.kind == ExtensionKind.mangayomi) {
      final value = decodeReadValue(
        await _invoke(module, '__terraMangayomiPages', chapter.href),
      );
      final json = value is Map ? value : const <Object?, Object?>{};
      final defaultHeaders = json['headers'] is Map
          ? (json['headers'] as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{};
      return soraList(json['pages'])
          .map(ReadPage.fromJson)
          .where((page) => page.url.isNotEmpty)
          .map(
            (page) => page.headers.isEmpty
                ? ReadPage(url: page.url, headers: defaultHeaders)
                : page,
          )
          .toList();
    }
    final argument = module.metadata.asyncJS
        ? chapter.href
        : await _fetch(chapter.href);
    return soraList(
      await _invoke(module, 'extractImages', argument),
    ).map(ReadPage.fromJson).where((page) => page.url.isNotEmpty).toList();
  }

  Future<String> readText(
    InstalledSoraModule module,
    ReadChapter chapter,
  ) async {
    final value = module.metadata.kind == ExtensionKind.mangayomi
        ? await _invoke(
            module,
            '__terraMangayomiText',
            '${chapter.title}\u0000${chapter.href}',
          )
        : await _invoke(
            module,
            'extractText',
            module.metadata.asyncJS ? chapter.href : await _fetch(chapter.href),
          );
    final decoded = decodeReadValue(value);
    if (decoded is List) return decoded.join('\n');
    if (decoded is Map) {
      return (decoded['html'] ?? decoded['content'] ?? decoded['text'] ?? '')
          .toString();
    }
    return decoded?.toString() ?? '';
  }

  Future<Object?> _invoke(
    InstalledSoraModule module,
    String function,
    Object argument,
  ) async {
    final script = await manager.readScript(module);
    final mangayomi = module.metadata.kind == ExtensionKind.mangayomi;
    final mangayomiSource = jsonEncode({
      ...module.metadata.extra,
      'id': module.metadata.extra['id'] ?? module.id,
      'name': module.metadata.sourceName,
      'baseUrl': module.metadata.baseUrl,
      'lang': module.metadata.language,
      'iconUrl': module.metadata.iconUrl,
      'version': module.metadata.version,
      'sourceCodeUrl': module.metadata.scriptUrl,
      'itemType': module.metadata.novel
          ? 2
          : module.metadata.type?.toLowerCase() == 'anime'
          ? 1
          : 0,
    });
    final wrapped = mangayomi
        ? '''$script
var __terraInstalledSource = $mangayomiSource;
var __terraScriptSources = typeof mangayomiSources !== 'undefined' ? mangayomiSources : [];
var __terraScriptSource = __terraScriptSources.find(function(source) { return String(source.id) === String(__terraInstalledSource.id) || (source.name === __terraInstalledSource.name && (!source.lang || source.lang === __terraInstalledSource.lang)); }) || __terraScriptSources[0] || {};
var __terraMangayomiSource = Object.assign({}, __terraScriptSource, __terraInstalledSource);
function __terraMangayomiExtension() { var extension = new DefaultExtension(); extension.source = __terraMangayomiSource; try { (extension.getSourcePreferences() || []).forEach(function(preference) { var value; if (preference.checkBoxPreference) value = preference.checkBoxPreference.value; else if (preference.switchPreferenceCompat) value = preference.switchPreferenceCompat.value; else if (preference.editTextPreference) value = preference.editTextPreference.value != null ? preference.editTextPreference.value : preference.editTextPreference.text; else if (preference.listPreference) { var index = preference.listPreference.valueIndex || 0; value = (preference.listPreference.entryValues || [])[index]; } else if (preference.multiSelectListPreference) value = preference.multiSelectListPreference.values; if (value != null) __terraPreferenceDefaults[preference.key] = value; }); } catch (_) {} return extension; }
function __terraFilterDefaults(filter) { if (!filter || typeof filter !== 'object') return filter; var type = filter.type_name; if (type === 'CheckBox' && filter.state == null) filter.state = false; else if (type === 'TriState' && filter.state == null) filter.state = 0; else if (type === 'SelectFilter') { if (filter.state == null) filter.state = 0; filter.values = (filter.values || []).map(__terraFilterDefaults); } else if (type === 'SortFilter') { if (filter.state == null) filter.state = {index: 0, ascending: false, type_name: 'SortState'}; filter.values = (filter.values || []).map(__terraFilterDefaults); } else if (type === 'GroupFilter') filter.state = (filter.state || []).map(__terraFilterDefaults); else if (type === 'TextFilter' && filter.state == null) filter.state = ''; return filter; }
async function __terraMangayomiSearch(query) { var extension = __terraMangayomiExtension(); if (typeof extension.search !== 'function') return JSON.stringify(typeof extension.getPopular === 'function' ? await extension.getPopular(1) : {list: [], hasNextPage: false}); var filters = []; try { filters = (extension.getFilterList() || []).map(__terraFilterDefaults); } catch (_) {} return JSON.stringify(await extension.search(query, 1, filters)); }
async function __terraMangayomiDetail(url) { return JSON.stringify(await __terraMangayomiExtension().getDetail(url)); }
async function __terraMangayomiVideos(url) { return JSON.stringify(await __terraMangayomiExtension().getVideoList(url)); }
async function __terraMangayomiPages(url) { var extension = __terraMangayomiExtension(); var headers = {}; try { headers = extension.getHeaders(url) || {}; } catch (_) {} return JSON.stringify({pages: await extension.getPageList(url), headers: headers}); }
async function __terraMangayomiText(value) { var extension = __terraMangayomiExtension(); var split = value.indexOf('\\u0000'); var name = value.slice(0, split); var url = value.slice(split + 1); return JSON.stringify(await extension.getHtmlContent(name, url)); }'''
        : script;
    final runtime =
        _runtimeOverride ?? _runtimes.putIfAbsent(module.id, SoraRuntime.new);
    return runtime.invoke(wrapped, function, [argument]);
  }

  Future<String> _fetch(String url) => soraRequest(
    url,
    timeout: const Duration(minutes: 1),
  ).then((response) => response.body);

  PlayerSource toPlayerSource({
    required InstalledSoraModule module,
    required SoraSearchResult result,
    required SoraEpisode episode,
    required SoraStreams sources,
    List<PlayerEpisodeEntry> episodes = const [],
    AsyncValueGetter<PlayerSource>? onNext,
    AsyncValueGetter<PlayerSource>? onPrevious,
    String? subtitleSearchQuery,
    bool subtitleSearchSeries = true,
    int subtitleSearchSeason = 1,
    int subtitleSearchEpisode = 1,
    String subtitleSearchLanguage = 'eng',
    PlayerSubtitleMediaSearch? onSearchSubtitleMedia,
    PlayerSubtitleSearch? onSearchSubtitles,
    PlayerProgressCallback? onProgress,
  }) {
    if (sources.streams.isEmpty)
      throw StateError('The extension returned no playable streams.');
    return PlayerSource(
      title: result.title,
      episodeLabel: episode.label,
      resumeKey: 'sora:${module.id}:${episode.href}',
      qualities: sources.streams
          .map(
            (stream) => PlayerQuality(
              label: stream.title,
              url: stream.url,
              headers: stream.headers,
            ),
          )
          .toList(),
      subtitleTracks: sources.subtitles
          .map(
            (subtitle) => PlayerSubtitleSource(
              label: subtitle.label,
              url: subtitle.url,
              language: subtitle.language,
            ),
          )
          .toList(),
      onNext: onNext,
      onPrevious: onPrevious,
      subtitleSearchQuery: subtitleSearchQuery,
      subtitleSearchSeries: subtitleSearchSeries,
      subtitleSearchSeason: subtitleSearchSeason,
      subtitleSearchEpisode: subtitleSearchEpisode,
      subtitleSearchLanguage: subtitleSearchLanguage,
      onSearchSubtitleMedia: onSearchSubtitleMedia,
      onSearchSubtitles: onSearchSubtitles,
      episodes: episodes,
      onProgress: onProgress,
    );
  }
}

List<Object?> _listField(Object? value, String field) {
  final decoded = decodeSoraValue(value);
  if (field.isNotEmpty && decoded is Map) return soraList(decoded[field]);
  return soraList(decoded);
}
