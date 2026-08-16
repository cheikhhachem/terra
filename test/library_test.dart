import 'package:flutter_test/flutter_test.dart';
import 'package:terra/features/library/library_models.dart';
import 'package:terra/features/library/library_repository.dart';
import 'package:terra/features/reading/reading_models.dart';

void main() {
  test('bookmark toggle persists and orders newest first', () async {
    final store = _MemoryLibraryStore();
    final repository = LibraryRepository(store: store);
    await repository.initialize();
    await repository.toggle(_media('old', DateTime.utc(2025)));
    await repository.toggle(_media('new', DateTime.utc(2026)));

    expect(repository.bookmarks.map((media) => media.id), ['new', 'old']);
    await repository.toggle(_media('old', DateTime.utc(2025)));
    expect(repository.bookmarks.map((media) => media.id), ['new']);

    final restored = LibraryRepository(store: store);
    await restored.initialize();
    expect(restored.bookmarks.map((media) => media.id), ['new']);
  });

  test('watching progress updates, orders, and removes at 90 percent', () async {
    final store = _MemoryLibraryStore();
    var now = DateTime.utc(2026, 1, 1);
    final repository = LibraryRepository(store: store, now: () => now);
    await repository.initialize();

    await _progress(repository, _media('first', now), const Duration(seconds: 2));
    expect(repository.continueWatching, isEmpty);
    await _progress(repository, _media('first', now), const Duration(minutes: 2));
    now = now.add(const Duration(minutes: 1));
    await _progress(repository, _media('second', now), const Duration(minutes: 3));
    expect(repository.continueWatching.map((entry) => entry.media.id), [
      'second',
      'first',
    ]);

    now = now.add(const Duration(minutes: 1));
    await repository.updateWatchingProgress(
      media: _media('first', now),
      episodeHref: 'episode-2',
      episodeLabel: 'Episode 2',
      episodeNumber: 2,
      season: 1,
      position: const Duration(minutes: 4),
      duration: const Duration(minutes: 10),
    );
    expect(repository.continueWatching.first.episodeHref, 'episode-2');

    await repository.updateWatchingProgress(
      media: _media('first', now),
      episodeHref: 'episode-2',
      episodeLabel: 'Episode 2',
      episodeNumber: 2,
      season: 1,
      position: const Duration(minutes: 9),
      duration: const Duration(minutes: 10),
    );
    expect(repository.continueWatching.map((entry) => entry.media.id), [
      'second',
    ]);

    final restored = LibraryRepository(store: store);
    await restored.initialize();
    expect(restored.continueWatching.single.media.id, 'second');
  });

  test('read bookmarks and reading position persist', () async {
    final store = _MemoryLibraryStore();
    final repository = LibraryRepository(store: store);
    await repository.initialize();
    final media = _readMedia('manga');
    const chapter = ReadChapter(
      href: 'chapter-4',
      title: 'Chapter 4',
      number: 4,
    );

    await repository.toggleRead(media);
    await repository.updateReadingProgress(
      media: media,
      chapter: chapter,
      chapterIndex: 3,
      position: .42,
    );

    final restored = LibraryRepository(store: store);
    await restored.initialize();
    expect(restored.readBookmarks.single.id, media.id);
    expect(restored.continueReading.single.chapterHref, 'chapter-4');
    expect(restored.continueReading.single.chapterIndex, 3);
    expect(restored.continueReading.single.position, .42);
  });
}

LibraryMedia _media(String id, DateTime addedAt) => LibraryMedia(
  id: id,
  moduleId: 'module',
  sourceName: 'Source',
  title: 'Title $id',
  imageUrl: 'https://example.test/$id.jpg',
  detailHref: 'https://example.test/$id',
  addedAt: addedAt,
);

ReadMedia _readMedia(String id) => ReadMedia(
  id: id,
  moduleId: 'read-module',
  sourceName: 'Read source',
  title: 'Title $id',
  imageUrl: 'https://example.test/$id.jpg',
  detailHref: 'https://example.test/$id',
  kind: ReadMediaKind.manga,
  addedAt: DateTime.utc(2026),
);

Future<void> _progress(
  LibraryRepository repository,
  LibraryMedia media,
  Duration position,
) => repository.updateWatchingProgress(
  media: media,
  episodeHref: 'episode-1',
  episodeLabel: 'Episode 1',
  episodeNumber: 1,
  season: 1,
  position: position,
  duration: const Duration(minutes: 10),
);

class _MemoryLibraryStore implements LibraryStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
