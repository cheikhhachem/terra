import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/extensions/extension_detail_repository.dart';
import 'package:terra/features/extensions/models.dart';

void main() {
  test('detail cache persists and restores a complete snapshot', () async {
    final store = _MemoryStore();
    final module = _module();
    final repository = ExtensionDetailRepository(
      store: store,
      now: () => DateTime.utc(2026, 8, 13),
      load: (_, _) async => (
        const SoraDetails(
          description: 'Description',
          imdbId: 'tt1234567',
          mediaType: 'series',
        ),
        const [
          SoraEpisode(
            href: '/episode-1',
            number: 1.5,
            title: 'Episode 1.5',
            imageUrl: 'https://example.test/episode.jpg',
            season: 2,
          ),
        ],
      ),
    );

    await repository.refresh(module, '/title');
    final restored = await ExtensionDetailRepository(
      store: store,
      load: (_, _) => throw UnimplementedError(),
    ).read(module, '/title');

    expect(restored!.details.description, 'Description');
    expect(restored.details.imdbId, 'tt1234567');
    expect(restored.episodes.single.number, 1.5);
    expect(restored.episodes.single.season, 2);
    expect(restored.updatedAt, DateTime.utc(2026, 8, 13));
  });

  test('failed refresh keeps the previous snapshot', () async {
    final store = _MemoryStore();
    final module = _module();
    await ExtensionDetailRepository(
      store: store,
      load: (_, _) async => (
        const SoraDetails(description: 'Cached'),
        const [SoraEpisode(href: '/episode', number: 1)],
      ),
    ).refresh(module, '/title');
    final failing = ExtensionDetailRepository(
      store: store,
      load: (_, _) => throw StateError('offline'),
    );

    await expectLater(failing.refresh(module, '/title'), throwsStateError);

    expect(
      (await failing.read(module, '/title'))!.details.description,
      'Cached',
    );
  });
}

InstalledSoraModule _module() => InstalledSoraModule(
  id: 'module',
  metadata: SoraMetadata.parse(
    jsonEncode({
      'sourceName': 'Source',
      'author': {'name': 'Author'},
      'scriptUrl': 'https://example.test/source.js',
      'version': '1',
    }),
  ),
  scriptPath: '/tmp/source.js',
  metadataUrl: 'https://example.test/source.json',
);

class _MemoryStore implements ExtensionDetailStore {
  final _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}
