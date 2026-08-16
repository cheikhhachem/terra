import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terra/features/player/player_logic.dart';
import 'package:terra/features/player/player_preferences.dart';
import 'package:terra/features/player/player_session.dart';
import 'package:terra/features/player/player_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source switch request retains headers and playback position', () {
    const quality = PlayerQuality(
      label: '1080p',
      url: 'https://example.test/1080.m3u8',
      headers: {'Referer': 'https://example.test/'},
    );
    final request = PlayerSession.openRequest(
      quality,
      const Duration(minutes: 12, seconds: 3),
    );
    expect(request.url, quality.url);
    expect(request.headers, quality.headers);
    expect(request.position, const Duration(minutes: 12, seconds: 3));
  });

  test('loaded URI tracks match their native selected copies', () {
    final subtitle = SubtitleTrack.uri(
      'https://example.test/en.srt',
      title: 'English',
      language: 'eng',
    );
    const nativeSubtitle = SubtitleTrack('3', 'English', 'eng');
    final audio = AudioTrack.uri(
      'https://example.test/japanese.m4a',
      title: 'Japanese',
      language: 'jpn',
    );
    const nativeAudio = AudioTrack('2', 'Japanese', 'jpn');

    expect(isSubtitleTrackActive(nativeSubtitle, subtitle), isTrue);
    expect(isAudioTrackActive(nativeAudio, audio), isTrue);
    expect(
      isSubtitleTrackActive(
        const SubtitleTrack('4', 'Spanish', 'spa'),
        subtitle,
      ),
      isFalse,
    );
  });

  test('auto tracks resolve to the first concrete visible option', () {
    const subtitles = [
      SubtitleTrack('no', null, null),
      SubtitleTrack('4', 'English', 'eng'),
    ];
    const audio = [
      AudioTrack('2', 'Japanese', 'jpn'),
      AudioTrack('3', 'English', 'eng'),
    ];

    expect(selectedSubtitleTrack(subtitles, SubtitleTrack.auto()).id, '4');
    expect(selectedAudioTrack(audio, AudioTrack.auto()).id, '2');
  });

  test('source subtitle is selected for a newly opened episode', () {
    final source = PlayerSource(
      title: 'Title',
      episodeLabel: 'Episode 1',
      resumeKey: 'episode-1',
      qualities: const [PlayerQuality(label: 'Auto', url: 'video')],
      subtitleTracks: const [
        PlayerSubtitleSource(
          label: 'English',
          url: 'https://example.test/en.srt',
          language: 'eng',
        ),
      ],
    );

    final track = preferredSourceSubtitle(source);
    expect(track!.id, 'https://example.test/en.srt');
    expect(track.title, 'English');
    expect(track.language, 'eng');
  });

  test('resume and player preferences persist without playback', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PlayerPreferences();
    await preferences.saveResumePosition(
      'episode-1',
      const Duration(minutes: 4),
    );
    await preferences.setDefaultRate(1.5);
    await preferences.setFit('cover');
    await preferences.setAutoplay(false);
    await preferences.setSubtitleSize(64);
    await preferences.setSubtitleBackgroundOpacity(.5);
    expect(
      await preferences.resumePosition('episode-1'),
      const Duration(minutes: 4),
    );
    expect(await preferences.defaultRate, 1.5);
    expect(await preferences.fit, 'cover');
    expect(await preferences.autoplay, isFalse);
    expect(await preferences.subtitleSize, 64);
    expect(await preferences.subtitleBackgroundOpacity, .5);
  });

  test('control state reveal, hide, and settings transitions are stable', () {
    const state = PlayerControlState();
    expect(state.hide().visible, isFalse);
    expect(state.hide().reveal().visible, isTrue);
    expect(state.setSettings(true).settingsOpen, isTrue);
    expect(state.setSettings(true).hide().settingsOpen, isTrue);
  });

  test('player episode catalog identifies one active entry', () {
    final source = PlayerSource(
      title: 'Title',
      episodeLabel: 'Episode 2',
      resumeKey: 'episode-2',
      qualities: const [PlayerQuality(label: 'Auto', url: 'video')],
      episodes: [
        PlayerEpisodeEntry(
          id: 'episode-1',
          label: 'Episode 1',
          season: 1,
          selected: false,
          load: () async => throw UnimplementedError(),
        ),
        PlayerEpisodeEntry(
          id: 'episode-2',
          label: 'Episode 2',
          season: 1,
          selected: true,
          load: () async => throw UnimplementedError(),
        ),
      ],
    );

    expect(
      source.episodes.singleWhere((entry) => entry.selected).id,
      'episode-2',
    );
  });

  test('episode entries load the next source in place', () async {
    final next = PlayerSource(
      title: 'Title',
      episodeLabel: 'Episode 2',
      resumeKey: 'episode-2',
      qualities: const [PlayerQuality(label: 'Auto', url: 'next-video')],
    );
    final entry = PlayerEpisodeEntry(
      id: 'episode-2',
      label: 'Episode 2',
      season: 1,
      selected: false,
      load: () async => next,
    );

    expect(await entry.load(), same(next));
  });
}
