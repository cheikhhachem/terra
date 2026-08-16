import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/sora_network.dart';
import 'package:terra/features/player/player_source.dart';
import 'package:terra/features/subtitles/subdl.dart';

void main() {
  test('builds SubDL episode request and parses raw unpacked files', () async {
    String? requestedUrl;
    final client = SubdlClient(
      request: (url) async {
        requestedUrl = url;
        return SoraHttpResponse(
          status: 200,
          headers: const {},
          body: jsonEncode({
            'status': true,
            'subtitles': [
              {
                'unpack_files': [
                  {
                    'language': 'AR',
                    'season': 1,
                    'episode': 24,
                    'release_name': 'Release',
                    'url': '/subtitle/parent/file',
                  },
                ],
              },
            ],
          }),
        );
      },
    );

    final tracks = await client.search(
      apiKey: 'key',
      media: const PlayerSubtitleMedia(
        imdbId: 'tt9058134',
        title: 'Kengan Ashura',
        series: true,
      ),
      language: 'ara',
      season: 1,
      episode: 24,
    );

    final uri = Uri.parse(requestedUrl!);
    expect(uri.queryParameters['languages'], 'AR');
    expect(uri.queryParameters['season_number'], '1');
    expect(uri.queryParameters['episode_number'], '24');
    expect(uri.queryParameters['unpack'], '1');
    expect(tracks.single.label, contains('SubDL'));
    expect(tracks.single.url, 'https://dl.subdl.com/subtitle/parent/file');
  });

  test('does nothing when no API key is configured', () async {
    final tracks = await const SubdlClient().search(
      apiKey: '',
      media: const PlayerSubtitleMedia(
        imdbId: 'tt0133093',
        title: 'The Matrix',
        series: false,
      ),
      language: 'eng',
      season: 1,
      episode: 1,
    );
    expect(tracks, isEmpty);
  });
}
