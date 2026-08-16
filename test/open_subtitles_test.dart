import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/sora_network.dart';
import 'package:terra/features/subtitles/open_subtitles.dart';

void main() {
  test('builds series endpoint and filters configured language', () async {
    String? requestedUrl;
    final client = OpenSubtitlesClient(
      request: (url) async {
        requestedUrl = url;
        return SoraHttpResponse(
          status: 200,
          headers: const {},
          body: jsonEncode({
            'subtitles': [
              {'id': '1', 'url': 'https://subs.example/english', 'lang': 'eng'},
              {'id': '2', 'url': 'https://subs.example/arabic', 'lang': 'ara'},
            ],
          }),
        );
      },
    );

    final results = await client.search(
      imdbId: 'tt0944947',
      series: true,
      language: 'ara',
      season: 1,
      episode: 2,
    );

    expect(
      requestedUrl,
      'https://opensubtitles-v3.strem.io/subtitles/series/tt0944947:1:2.json',
    );
    expect(results, hasLength(1));
    expect(results.single.language, 'ara');
    expect(results.single.label, contains('Arabic'));
  });

  test('rejects invalid IMDb identifiers', () async {
    expect(
      () => const OpenSubtitlesClient().search(
        imdbId: 'matrix',
        series: false,
        language: 'eng',
      ),
      throwsFormatException,
    );
  });

  test('searches titles and returns IMDb media candidates', () async {
    String? requestedUrl;
    final client = OpenSubtitlesClient(
      request: (url) async {
        requestedUrl = url;
        return SoraHttpResponse(
          status: 200,
          headers: const {},
          body: jsonEncode({
            'metas': [
              {
                'id': 'tt0944947',
                'name': 'Game of Thrones',
                'type': 'series',
                'releaseInfo': '2011-2019',
                'poster': 'https://example.test/poster.jpg',
              },
            ],
          }),
        );
      },
    );

    final results = await client.searchMedia(
      query: 'Game of Thrones',
      series: true,
    );

    expect(requestedUrl, contains('search=Game%20of%20Thrones.json'));
    expect(results.single.imdbId, 'tt0944947');
    expect(results.single.series, isTrue);
    expect(results.single.year, '2011-2019');
  });

  test('Kengan Ashura coverage differs by episode and language', () async {
    final responses = {
      '1': ['eng', 'ara'],
      '24': ['eng'],
    };
    final client = OpenSubtitlesClient(
      request: (url) async {
        final episode = url.contains(':24.json') ? '24' : '1';
        return SoraHttpResponse(
          status: 200,
          headers: const {},
          body: jsonEncode({
            'subtitles': [
              for (final language in responses[episode]!)
                {
                  'url': 'https://subs.example/$language/$episode',
                  'lang': language,
                },
            ],
          }),
        );
      },
    );

    expect(
      await client.search(
        imdbId: 'tt9058134',
        series: true,
        language: 'ara',
        episode: 1,
      ),
      hasLength(1),
    );
    expect(
      await client.search(
        imdbId: 'tt9058134',
        series: true,
        language: 'ara',
        episode: 24,
      ),
      isEmpty,
    );
  });
}
