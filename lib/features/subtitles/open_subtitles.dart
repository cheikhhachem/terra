import 'dart:convert';

import '../extensions/sora_network.dart';
import '../player/player_source.dart';

const subtitleLanguages = <String, String>{
  'English': 'eng',
  'Arabic': 'ara',
  'French': 'fre',
  'Spanish': 'spa',
  'German': 'ger',
  'Italian': 'ita',
  'Portuguese': 'por',
  'Portuguese (Brazil)': 'pob',
  'Turkish': 'tur',
  'Russian': 'rus',
  'Polish': 'pol',
  'Dutch': 'nld',
  'Indonesian': 'ind',
  'Japanese': 'jpn',
  'Korean': 'kor',
  'Chinese': 'chi',
};

typedef SubtitleRequest = Future<SoraHttpResponse> Function(String url);

class OpenSubtitlesClient {
  const OpenSubtitlesClient({SubtitleRequest request = soraRequest})
    : _request = request;

  final SubtitleRequest _request;

  Future<List<PlayerSubtitleMedia>> searchMedia({
    required String query,
    required bool series,
  }) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final type = series ? 'series' : 'movie';
    final response = await _request(
      'https://v3-cinemeta.strem.io/catalog/$type/top/search=${Uri.encodeComponent(value)}.json',
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Title search returned HTTP ${response.status}.');
    }
    final decoded = jsonDecode(response.body);
    final values = decoded is Map ? decoded['metas'] : null;
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((item) {
          final id =
              item['imdb_id']?.toString() ?? item['id']?.toString() ?? '';
          final title = item['name']?.toString() ?? '';
          if (!RegExp(r'^tt\d{7,10}$').hasMatch(id) || title.isEmpty) {
            return null;
          }
          return PlayerSubtitleMedia(
            imdbId: id,
            title: title,
            series: item['type'] == 'series',
            year: (item['releaseInfo'] ?? item['year'])?.toString(),
            posterUrl: item['poster']?.toString(),
          );
        })
        .whereType<PlayerSubtitleMedia>()
        .take(20)
        .toList();
  }

  Future<List<PlayerSubtitleSource>> search({
    required String imdbId,
    required bool series,
    required String language,
    int season = 1,
    int episode = 1,
  }) async {
    if (!RegExp(r'^tt\d{7,10}$').hasMatch(imdbId)) {
      throw const FormatException('A valid IMDb ID is required.');
    }
    final id = series ? '$imdbId:$season:$episode' : imdbId;
    final type = series ? 'series' : 'movie';
    final response = await _request(
      'https://opensubtitles-v3.strem.io/subtitles/$type/$id.json',
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('OpenSubtitles returned HTTP ${response.status}.');
    }
    final decoded = jsonDecode(response.body);
    final values = decoded is Map ? decoded['subtitles'] : null;
    if (values is! List) return const [];
    var index = 0;
    return values
        .whereType<Map>()
        .where((item) => item['lang'] == language)
        .map((item) {
          final url = Uri.tryParse(item['url']?.toString() ?? '');
          if (url == null || url.scheme != 'https') return null;
          index++;
          return PlayerSubtitleSource(
            label: 'OpenSubtitles · ${subtitleLanguageName(language)} · $index',
            url: url.toString(),
            language: language,
          );
        })
        .whereType<PlayerSubtitleSource>()
        .take(20)
        .toList();
  }
}

String subtitleLanguageName(String code) =>
    subtitleLanguages.entries
        .where((entry) => entry.value == code)
        .map((entry) => entry.key)
        .firstOrNull ??
    code;
