// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:terra/app.dart';
import 'package:terra/features/player/player_source.dart';

void main() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  testWidgets('shows the Terra media library', (WidgetTester tester) async {
    await tester.pumpWidget(Application());

    expect(find.text('Terra'), findsOneWidget);
    expect(find.text('Library'), findsAtLeastNWidgets(1));
  });

  test('player source keeps direct quality and subtitles', () {
    final source = PlayerSource(
      title: 'Title',
      episodeLabel: 'Episode 1',
      resumeKey: 'episode-1',
      qualities: [
        PlayerQuality(
          label: '720p',
          url: 'https://example.test/video.m3u8',
          headers: {'Authorization': 'Bearer token'},
        ),
      ],
      subtitleTracks: [
        PlayerSubtitleSource(
          label: 'English',
          url: 'https://example.test/subtitles.vtt',
        ),
      ],
    );
    expect(source.qualities.single.label, '720p');
    expect(source.qualities.single.headers['Authorization'], 'Bearer token');
    expect(source.subtitleTracks.single.label, 'English');
  });
}
