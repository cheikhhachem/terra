import 'dart:convert';

import '../extensions/sora_network.dart';

class MangaDexClient {
  const MangaDexClient({this.request = soraRequest});

  final Future<SoraHttpResponse> Function(String url) request;

  Future<List<MangaDexSuggestion>> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final response = await request(
      'https://api.mangadex.org/manga?'
      'title=${Uri.encodeComponent(value)}'
      '&limit=10'
      '&contentRating[]=safe'
      '&contentRating[]=suggestive'
      '&contentRating[]=erotica'
      '&includes[]=cover_art',
    );
    if (response.status < 200 || response.status >= 300) return const [];
    final decoded = jsonDecode(response.body);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) {
          final attributes = item['attributes'];
          if (attributes is! Map) return null;
          final titleMap = attributes['title'];
          if (titleMap is! Map) return null;
          final title = titleMap['en']?.toString() ??
              titleMap.values.firstOrNull?.toString() ??
              '';
          if (title.isEmpty) return null;
          final relationships = item['relationships'];
          String? coverFileName;
          if (relationships is List) {
            final cover = relationships
                .whereType<Map>()
                .firstWhere(
                  (rel) => rel['type'] == 'cover_art',
                  orElse: () => const <String, dynamic>{},
                );
            final coverAttributes = cover['attributes'];
            if (coverAttributes is Map) {
              coverFileName = coverAttributes['fileName']?.toString();
            }
          }
          final mangaId = item['id']?.toString() ?? '';
          final posterUrl = coverFileName != null && mangaId.isNotEmpty
              ? 'https://mangadex.org/covers/$mangaId/$coverFileName'
              : null;
          return MangaDexSuggestion(
            mangaId: mangaId,
            title: title,
            posterUrl: posterUrl,
          );
        })
        .whereType<MangaDexSuggestion>()
        .take(8)
        .toList();
  }
}

class MangaDexSuggestion {
  const MangaDexSuggestion({
    required this.mangaId,
    required this.title,
    this.posterUrl,
  });

  final String mangaId;
  final String title;
  final String? posterUrl;
}
