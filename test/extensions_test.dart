import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/extension_manager.dart';
import 'package:terra/features/extensions/models.dart';
import 'package:terra/features/extensions/sora_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manifest accepts real optional and extra fields', () {
    final metadata = SoraMetadata.parse(
      jsonEncode({
        'sourceName': 'Fixture',
        'author': {
          'name': 'Author',
          'icon': 'icon',
          'url': 'profile',
          'handle': '@author',
        },
        'scriptUrl': 'fixture.js',
        'asyncJS': true,
        'languageType': ['Subbed', 'Dubbed'],
        'downloadSupport': true,
      }),
    );

    expect(metadata.sourceName, 'Fixture');
    expect(metadata.asyncJS, isTrue);
    expect(metadata.extra['languageType'], ['Subbed', 'Dubbed']);
    expect(metadata.extra['downloadSupport'], isTrue);
    expect(metadata.author.extra['handle'], '@author');
  });

  test('manifest accepts legacy uppercase URL fields', () {
    final metadata = SoraMetadata.parse(
      jsonEncode({
        'sourceName': 'Manga fixture',
        'author': {'name': 'Author'},
        'scriptURL': 'manga.js',
        'iconURL': 'icon.png',
        'type': 'mangas',
      }),
    );

    expect(metadata.scriptUrl, 'manga.js');
    expect(metadata.iconUrl, 'icon.png');
  });

  test('streamAsyncJS remains opt-in for async extensions', () {
    final metadata = SoraMetadata.parse(
      jsonEncode({
        'sourceName': 'Fixture',
        'author': {'name': 'Author'},
        'scriptUrl': 'fixture.js',
        'asyncJS': true,
      }),
    );

    expect(metadata.asyncJS, isTrue);
    expect(metadata.streamAsyncJS, isFalse);
  });

  test('normalizes fixture result variants', () {
    final search = soraList(
      jsonEncode([
        {'name': 'Title', 'poster': 'image', 'url': 'detail'},
      ]),
    ).map(SoraSearchResult.fromJson).single;
    final episode = SoraEpisode.fromJson({
      'id': 42,
      'episode': '2.5',
      'thumbnail': 'thumb',
    }, 0);
    final sources = SoraStreams.fromValue(
      jsonEncode({
        'stream': {
          'file': 'https://example.test/video.m3u8',
          'quality': '1080p',
          'headers': {'Referer': 'https://example.test/'},
          'subtitle': 'https://example.test/embedded.vtt',
        },
        'tracks': [
          {'src': 'https://example.test/sub.vtt', 'lang': 'en'},
        ],
      }),
    );

    expect(
      (search.title, search.imageUrl, search.href),
      ('Title', 'image', 'detail'),
    );
    expect(
      (episode.href, episode.number, episode.imageUrl),
      ('42', 2.5, 'thumb'),
    );
    expect(sources.streams.single.title, '1080p');
    expect(sources.streams.single.headers['Referer'], 'https://example.test/');
    expect(sources.subtitles, hasLength(2));
    expect(sources.subtitles.first.language, 'en');
    expect(sources.subtitles.last.url, 'https://example.test/embedded.vtt');
  });

  test('search results preserve OpenSubtitles identity', () {
    final result = SoraSearchResult.fromJson({
      'name': 'Movie',
      'url': '/movie',
      'imdb_id': 'tt0133093',
      'type': 'Films',
    });

    expect(result.imdbId, 'tt0133093');
    expect(result.mediaType, 'movie');
  });

  test('keeps Sora alternating subtitle labels', () {
    final sources = SoraStreams.fromValue({
      'stream': 'https://example.test/video.m3u8',
      'subtitles': [
        'English',
        'https://example.test/en.vtt',
        'Spanish',
        'https://example.test/es.vtt',
      ],
    });

    expect(
      sources.subtitles.map((subtitle) => (subtitle.label, subtitle.url)),
      [
        ('English', 'https://example.test/en.vtt'),
        ('Spanish', 'https://example.test/es.vtt'),
      ],
    );
  });

  test('episodes group by normalized season with stable decimal ordering', () {
    const episodes = [
      SoraEpisode(href: 'late', number: 2, season: 2),
      SoraEpisode(href: 'decimal', number: 1.5),
      SoraEpisode(href: 'first-tie', number: 1),
      SoraEpisode(href: 'second-tie', number: 1),
    ];

    final ascending = groupSoraEpisodesBySeason(episodes);
    expect(ascending.keys, [1, 2]);
    expect(ascending[1]!.map((episode) => episode.href), [
      'first-tie',
      'second-tie',
      'decimal',
    ]);
    expect(
      groupSoraEpisodesBySeason(
        episodes,
        ascending: false,
      )[1]!.map((episode) => episode.href),
      ['decimal', 'first-tie', 'second-tie'],
    );
  });

  test('infers IMDb.su season from title and URL', () {
    final fromTitle = SoraEpisode.fromJson({
      'href': 'episode-id',
      'number': 3,
      'title': 'S2 E3 - Example',
    }, 0);
    final fromUrl = SoraEpisode.fromJson({
      'href': 'https://player.imdb.su/embed/tv/tt1234567/4/8',
      'number': 8,
    }, 0);

    expect(fromTitle.season, 2);
    expect(fromUrl.season, 4);
  });

  test(
    'QuickJS resolves a Promise result',
    () async {
      final runtime = SoraRuntime(timeout: const Duration(seconds: 3));
      final result = await runtime.invoke(
        'async function mock(value) { return JSON.stringify({value: value + 1}); }',
        'mock',
        [41],
      );

      expect(jsonDecode(result.toString()), {'value': 42});
      runtime.dispose();
    },
    skip: !Platform.isAndroid && Platform.environment['SORA_QJS_TEST'] != '1'
        ? 'flutter_qjs native symbols are linked by the Android application, not the host flutter_tester.'
        : false,
  );

  test('known source install and uninstall states are separate', () async {
    final directory = await Directory.systemTemp.createTemp('sora_extensions_');
    var scriptDownloads = 0;
    final manager = ExtensionManager(
      store: _MemoryExtensionStore(),
      download: (url, label) async {
        if (label == 'script') {
          scriptDownloads++;
          return 'function searchResults() { return "[]"; }';
        }
        return jsonEncode({
          'sourceName': 'Test source',
          'author': {'name': 'Test'},
          'scriptUrl': 'source.js',
          'language': 'English',
          'type': 'Anime',
        });
      },
      directory: () async => directory,
    );
    await manager.initialize();

    final source = await manager.addSource('https://example.test/source.json');
    expect(manager.knownSources, hasLength(1));
    expect(manager.installed, isEmpty);
    expect(scriptDownloads, 0);

    final installed = await manager.install(source);
    expect(installed.active, isTrue);
    expect(manager.activeInstalled, hasLength(1));
    expect(scriptDownloads, 1);

    await manager.refresh(source, 'https://example.test/updated.json');
    expect(
      manager.knownSources.single.metadataUrl,
      'https://example.test/updated.json',
    );
    expect(
      manager.installed.single.metadataUrl,
      'https://example.test/updated.json',
    );

    await manager.uninstall(manager.knownSources.single);
    expect(manager.knownSources, hasLength(1));
    expect(manager.installed, isEmpty);
    expect(await File(installed.scriptPath).exists(), isFalse);
    await directory.delete(recursive: true);
  });

  test('unchanged refresh does not download or rewrite the script', () async {
    final directory = await Directory.systemTemp.createTemp('sora_refresh_');
    var scriptDownloads = 0;
    final manifest = jsonEncode({
      'sourceName': 'Test source',
      'author': {'name': 'Test'},
      'scriptUrl': 'source.js',
    });
    final manager = ExtensionManager(
      store: _MemoryExtensionStore(),
      download: (_, label) async {
        if (label == 'script') {
          scriptDownloads++;
          return 'script $scriptDownloads';
        }
        return manifest;
      },
      directory: () async => directory,
    );
    await manager.initialize();
    final source = await manager.addSource('https://example.test/source.json');
    final installed = await manager.install(source);

    await manager.refreshAllSources();

    expect(scriptDownloads, 1);
    expect(await File(installed.scriptPath).readAsString(), 'script 1');
    await directory.delete(recursive: true);
  });

  test('Mangayomi repository adds JavaScript watch and read sources', () async {
    final directory = await Directory.systemTemp.createTemp('mangayomi_');
    final manager = ExtensionManager(
      store: _MemoryExtensionStore(),
      download: (_, label) async {
        if (label == 'script') {
          return 'class DefaultExtension extends MProvider {}';
        }
        return jsonEncode([
          {
            'id': 1,
            'name': 'Anime source',
            'lang': 'en',
            'baseUrl': 'https://example.test',
            'iconUrl': 'https://example.test/icon.png',
            'version': '1.0.0',
            'sourceCodeUrl': 'https://example.test/anime.js',
            'sourceCodeLanguage': 1,
            'isManga': false,
            'itemType': 1,
          },
          {
            'id': 3,
            'name': 'Second anime source',
            'lang': 'fr',
            'baseUrl': 'https://second.example.test',
            'iconUrl': 'https://second.example.test/icon.png',
            'version': '2.0.0',
            'sourceCodeUrl': 'https://example.test/second.js',
            'sourceCodeLanguage': 1,
            'isManga': false,
            'itemType': 1,
          },
          {
            'id': 4,
            'name': 'Dart anime source',
            'sourceCodeUrl': 'https://example.test/anime.dart',
            'sourceCodeLanguage': 0,
            'isManga': false,
            'itemType': 1,
          },
          {
            'id': 2,
            'name': 'Manga source',
            'sourceCodeUrl': 'https://example.test/manga.js',
            'isManga': true,
            'itemType': 0,
          },
          {
            'id': 5,
            'name': 'Novel source',
            'sourceCodeUrl': 'https://example.test/novel.js',
            'sourceCodeLanguage': 1,
            'isManga': false,
            'itemType': 2,
          },
          {
            'id': 6,
            'name': 'Mihon source',
            'sourceCodeUrl': 'https://example.test/mihon.apk',
            'sourceCodeLanguage': 2,
            'itemType': 0,
          },
        ]);
      },
      directory: () async => directory,
    );
    await manager.initialize();

    await manager.addSource('https://example.test/anime_index.json');

    expect(manager.knownSources, hasLength(4));
    expect(manager.knownSources.first.metadata.kind, ExtensionKind.mangayomi);
    expect(manager.knownSources.first.metadata.sourceName, 'Anime source');
    final installed = await manager.install(manager.knownSources.first);
    await manager.install(
      manager.knownSources.singleWhere(
        (source) => source.metadata.sourceName == 'Manga source',
      ),
    );
    await manager.install(
      manager.knownSources.singleWhere(
        (source) => source.metadata.sourceName == 'Novel source',
      ),
    );
    expect(await File(installed.scriptPath).exists(), isTrue);
    expect(manager.activeWatchInstalled, hasLength(1));
    expect(manager.activeReadInstalled, hasLength(2));
    expect(
      manager.knownSources
          .singleWhere((source) => source.metadata.sourceName == 'Novel source')
          .metadata
          .novel,
      isTrue,
    );

    await manager.refreshSources(
      manager.knownSources,
      'https://example.test/updated_index.json',
    );
    expect(manager.knownSources.map((source) => source.metadataUrl).toSet(), {
      'https://example.test/updated_index.json',
    });

    await manager.removeSources(manager.knownSources);
    expect(manager.knownSources, isEmpty);
    expect(manager.installed, isEmpty);
    expect(await File(installed.scriptPath).exists(), isFalse);
    await directory.delete(recursive: true);
  });

  test('legacy installed registry migrates as known active source', () async {
    final directory = await Directory.systemTemp.createTemp('sora_migration_');
    final script = File('${directory.path}/legacy.js');
    await script.writeAsString('legacy');
    final legacy = InstalledSoraModule(
      id: 'legacy',
      metadata: SoraMetadata.parse(
        jsonEncode({
          'sourceName': 'Legacy',
          'author': {'name': 'Test'},
          'scriptUrl': 'https://example.test/legacy.js',
        }),
      ),
      scriptPath: script.path,
      metadataUrl: 'https://example.test/legacy.json',
    );
    final manager = ExtensionManager(
      store: _MemoryExtensionStore({
        'sora.modules.v1': jsonEncode([legacy.toJson()]),
        'sora.selectedModule.v1': 'legacy',
      }),
      directory: () async => directory,
    );
    await manager.initialize();

    expect(manager.knownSources.single.id, 'legacy');
    expect(manager.installed.single.id, 'legacy');
    expect(manager.activeInstalled.single.id, 'legacy');
    await directory.delete(recursive: true);
  });
}

class _MemoryExtensionStore implements ExtensionStore {
  _MemoryExtensionStore([Map<String, String>? values]) : _values = values ?? {};
  final Map<String, String> _values;

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}
