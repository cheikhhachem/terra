import 'dart:convert';

import '../extensions/sora_network.dart';

class CinemetaClient {
  const CinemetaClient({this.request = soraRequest});

  final Future<SoraHttpResponse> Function(String url) request;

  Future<List<CinemetaSuggestion>> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final results = await Future.wait([
      _fetch('movie', value),
      _fetch('series', value),
    ]);
    return [...results[0], ...results[1]];
  }

  Future<List<CinemetaSuggestion>> _fetch(String type, String query) async {
    final response = await request(
      'https://v3-cinemeta.strem.io/catalog/$type/top/search=${Uri.encodeComponent(query)}.json',
    );
    if (response.status < 200 || response.status >= 300) return const [];
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
          return CinemetaSuggestion(
            imdbId: id,
            title: title,
            year: (item['releaseInfo'] ?? item['year'])?.toString(),
            posterUrl: item['poster']?.toString(),
          );
        })
        .whereType<CinemetaSuggestion>()
        .take(8)
        .toList();
  }
}

class CinemetaSuggestion {
  const CinemetaSuggestion({
    required this.imdbId,
    required this.title,
    this.year,
    this.posterUrl,
  });

  final String imdbId;
  final String title;
  final String? year;
  final String? posterUrl;
}
