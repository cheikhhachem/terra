import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../extensions/sora_network.dart';
import '../player/player_source.dart';
import 'open_subtitles.dart';

const subdlLanguageCodes = <String, String>{
  'eng': 'EN',
  'ara': 'AR',
  'fre': 'FR',
  'spa': 'ES',
  'ger': 'DE',
  'ita': 'IT',
  'por': 'PT',
  'pob': 'BR_PT',
  'tur': 'TR',
  'rus': 'RU',
  'pol': 'PL',
  'nld': 'NL',
  'ind': 'ID',
  'jpn': 'JA',
  'kor': 'KO',
  'chi': 'ZH',
};

class SubdlClient {
  const SubdlClient({SubtitleRequest request = soraRequest})
    : _request = request;

  final SubtitleRequest _request;

  Future<List<PlayerSubtitleSource>> search({
    required String apiKey,
    required PlayerSubtitleMedia media,
    required String language,
    required int season,
    required int episode,
  }) async {
    final subdlLanguage = subdlLanguageCodes[language];
    if (apiKey.trim().isEmpty || subdlLanguage == null) return const [];
    final query = <String, String>{
      'api_key': apiKey.trim(),
      'imdb_id': media.imdbId,
      'type': media.series ? 'tv' : 'movie',
      'languages': subdlLanguage,
      'subs_per_page': '30',
      'releases': '1',
      'unpack': '1',
      'client': 'custom_integration',
      if (media.series) 'season_number': '$season',
      if (media.series) 'episode_number': '$episode',
    };
    final response = await _request(
      Uri.https('api.subdl.com', '/api/v1/subtitles', query).toString(),
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('SubDL returned HTTP ${response.status}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['status'] != true) {
      throw StateError(
        decoded is Map ? '${decoded['error']}' : 'Invalid SubDL response.',
      );
    }
    final subtitles = decoded['subtitles'];
    if (subtitles is! List) return const [];
    var index = 0;
    final results = <PlayerSubtitleSource>[];
    for (final subtitle in subtitles.whereType<Map>()) {
      final files = subtitle['unpack_files'];
      for (final file
          in files is List ? files.whereType<Map>() : const <Map>[]) {
        if (file['language']?.toString().toUpperCase() != subdlLanguage ||
            (media.series &&
                (_int(file['season']) != season ||
                    _int(file['episode']) != episode))) {
          continue;
        }
        final path = file['url']?.toString() ?? '';
        if (path.isEmpty) continue;
        final url = Uri.parse('https://dl.subdl.com').resolve(path);
        index++;
        results.add(
          PlayerSubtitleSource(
            label:
                'SubDL · ${subtitleLanguageName(language)} · ${file['release_name'] ?? file['name'] ?? index}',
            url: url.toString(),
            language: language,
          ),
        );
      }
      if (files is! List || files.isEmpty) {
        final path = subtitle['url']?.toString() ?? '';
        if (path.isEmpty) continue;
        final archiveUrl = Uri.parse('https://dl.subdl.com').resolve(path);
        index++;
        results.add(
          PlayerSubtitleSource(
            label:
                'SubDL · ${subtitleLanguageName(language)} · ${subtitle['release_name'] ?? subtitle['name'] ?? index}',
            url: archiveUrl.toString(),
            language: language,
            resolveUrl: () => _extractSubtitle(archiveUrl, '$index'),
          ),
        );
      }
    }
    return results.take(20).toList();
  }
}

Future<String> _extractSubtitle(Uri uri, String id) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('SubDL download returned HTTP ${response.statusCode}.');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 20 * 1024 * 1024) {
        throw StateError('SubDL subtitle archive is too large.');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = archive.files.where((file) {
      final name = file.name.toLowerCase();
      return file.isFile &&
          !name.contains('..') &&
          !name.startsWith('/') &&
          (name.endsWith('.srt') ||
              name.endsWith('.ass') ||
              name.endsWith('.ssa') ||
              name.endsWith('.vtt'));
    }).toList();
    if (files.isEmpty) throw StateError('SubDL archive has no subtitle file.');
    files.sort(
      (a, b) => _subtitleRank(a.name).compareTo(_subtitleRank(b.name)),
    );
    final file = files.first;
    if (file.size > 5 * 1024 * 1024) {
      throw StateError('SubDL subtitle file is too large.');
    }
    final extension = file.name.split('.').last.toLowerCase();
    final directory = await getTemporaryDirectory();
    final output = File('${directory.path}/terra_subdl_$id.$extension');
    final content = file.readBytes();
    if (content == null) throw StateError('Could not read SubDL subtitle.');
    await output.writeAsBytes(content, flush: true);
    return output.path;
  } finally {
    client.close(force: true);
  }
}

int _subtitleRank(String name) => switch (name.toLowerCase().split('.').last) {
  'srt' => 0,
  'ass' => 1,
  'ssa' => 2,
  'vtt' => 3,
  _ => 4,
};

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
