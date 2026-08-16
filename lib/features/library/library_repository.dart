import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../reading/reading_models.dart';
import 'library_models.dart';

abstract interface class LibraryStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesLibraryStore implements LibraryStore {
  SharedPreferencesLibraryStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class LibraryRepository extends ChangeNotifier {
  LibraryRepository({LibraryStore? store, DateTime Function()? now})
    : _store = store ?? SharedPreferencesLibraryStore(),
      _now = now ?? DateTime.now;

  static const bookmarksKey = 'sora.library.bookmarks.v1';
  static const continueWatchingKey = 'sora.library.continue.v1';
  static const readBookmarksKey = 'terra.library.read.bookmarks.v1';
  static const continueReadingKey = 'terra.library.read.continue.v1';

  final LibraryStore _store;
  final DateTime Function() _now;
  final List<LibraryMedia> _bookmarks = [];
  final List<ContinueWatchingEntry> _continueWatching = [];
  final List<ReadMedia> _readBookmarks = [];
  final List<ContinueReadingEntry> _continueReading = [];
  bool initialized = false;

  List<LibraryMedia> get bookmarks => List.unmodifiable(_bookmarks);
  List<ContinueWatchingEntry> get continueWatching =>
      List.unmodifiable(_continueWatching);
  List<ReadMedia> get readBookmarks => List.unmodifiable(_readBookmarks);
  List<ContinueReadingEntry> get continueReading =>
      List.unmodifiable(_continueReading);

  Future<void> initialize() async {
    if (initialized) return;
    _bookmarks
      ..clear()
      ..addAll(await _decode(bookmarksKey, LibraryMedia.tryFromJson));
    _continueWatching
      ..clear()
      ..addAll(
        await _decode(continueWatchingKey, ContinueWatchingEntry.tryFromJson),
      );
    _readBookmarks
      ..clear()
      ..addAll(await _decode(readBookmarksKey, ReadMedia.tryFromJson));
    _continueReading
      ..clear()
      ..addAll(
        await _decode(continueReadingKey, ContinueReadingEntry.tryFromJson),
      );
    _sort();
    initialized = true;
    notifyListeners();
  }

  bool contains(String mediaId) =>
      _bookmarks.any((media) => media.id == mediaId);

  Future<void> toggle(LibraryMedia media) =>
      contains(media.id) ? remove(media.id) : add(media);

  Future<void> add(LibraryMedia media) async {
    _bookmarks.removeWhere((item) => item.id == media.id);
    _bookmarks.add(media);
    _sort();
    notifyListeners();
    await _saveBookmarks();
  }

  Future<void> remove(String mediaId) async {
    final changed = _bookmarks.length;
    _bookmarks.removeWhere((media) => media.id == mediaId);
    if (changed == _bookmarks.length) return;
    notifyListeners();
    await _saveBookmarks();
  }

  Future<void> updateWatchingProgress({
    required LibraryMedia media,
    required String episodeHref,
    required String episodeLabel,
    required double episodeNumber,
    required int season,
    required Duration position,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero || position < Duration.zero) return;
    final progress = position.inMilliseconds / duration.inMilliseconds;
    if (!progress.isFinite) return;
    if (progress >= .9) {
      await removeWatching(media.id);
      return;
    }
    final existing = _continueWatching.indexWhere(
      (entry) => entry.media.id == media.id,
    );
    if (existing < 0 && position < const Duration(seconds: 5)) return;
    final entry = ContinueWatchingEntry(
      media: existing < 0
          ? media
          : LibraryMedia(
              id: media.id,
              moduleId: media.moduleId,
              sourceName: media.sourceName,
              title: media.title,
              imageUrl: media.imageUrl,
              detailHref: media.detailHref,
              addedAt: _continueWatching[existing].media.addedAt,
            ),
      episodeHref: episodeHref,
      episodeLabel: episodeLabel,
      episodeNumber: episodeNumber,
      season: season,
      position: position > duration ? duration : position,
      duration: duration,
      updatedAt: _now(),
    );
    if (existing >= 0) _continueWatching.removeAt(existing);
    _continueWatching.add(entry);
    _sort();
    notifyListeners();
    await _saveWatching();
  }

  Future<void> removeWatching(String mediaId) async {
    final length = _continueWatching.length;
    _continueWatching.removeWhere((entry) => entry.media.id == mediaId);
    if (length == _continueWatching.length) return;
    notifyListeners();
    await _saveWatching();
  }

  bool containsRead(String mediaId) =>
      _readBookmarks.any((media) => media.id == mediaId);

  Future<void> toggleRead(ReadMedia media) =>
      containsRead(media.id) ? removeRead(media.id) : addRead(media);

  Future<void> addRead(ReadMedia media) async {
    _readBookmarks.removeWhere((item) => item.id == media.id);
    _readBookmarks.add(media);
    _sort();
    notifyListeners();
    await _saveReadBookmarks();
  }

  Future<void> removeRead(String mediaId) async {
    final length = _readBookmarks.length;
    _readBookmarks.removeWhere((media) => media.id == mediaId);
    if (length == _readBookmarks.length) return;
    notifyListeners();
    await _saveReadBookmarks();
  }

  Future<void> updateReadingProgress({
    required ReadMedia media,
    required ReadChapter chapter,
    required int chapterIndex,
    required double position,
  }) async {
    if (!position.isFinite) return;
    final existing = _continueReading.indexWhere(
      (entry) => entry.media.id == media.id,
    );
    final entry = ContinueReadingEntry(
      media: existing < 0
          ? media
          : ReadMedia(
              id: media.id,
              moduleId: media.moduleId,
              sourceName: media.sourceName,
              title: media.title,
              imageUrl: media.imageUrl,
              detailHref: media.detailHref,
              kind: media.kind,
              addedAt: _continueReading[existing].media.addedAt,
            ),
      chapterHref: chapter.href,
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      position: position.clamp(0, 1),
      updatedAt: _now(),
    );
    if (existing >= 0) _continueReading.removeAt(existing);
    _continueReading.add(entry);
    _sort();
    notifyListeners();
    await _saveReading();
  }

  Future<void> removeReading(String mediaId) async {
    final length = _continueReading.length;
    _continueReading.removeWhere((entry) => entry.media.id == mediaId);
    if (length == _continueReading.length) return;
    notifyListeners();
    await _saveReading();
  }

  Future<List<T>> _decode<T>(
    String key,
    T? Function(Object? value) decode,
  ) async {
    try {
      final value = jsonDecode(await _store.getString(key) ?? '[]');
      if (value is! List) return [];
      final decoded = <T>[];
      for (final item in value) {
        final result = decode(item);
        if (result != null) decoded.add(result);
      }
      return decoded;
    } on FormatException {
      return [];
    }
  }

  void _sort() {
    _bookmarks.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    _continueWatching.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _readBookmarks.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    _continueReading.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _saveBookmarks() => _store.setString(
    bookmarksKey,
    jsonEncode(_bookmarks.map((media) => media.toJson()).toList()),
  );

  Future<void> _saveWatching() => _store.setString(
    continueWatchingKey,
    jsonEncode(_continueWatching.map((entry) => entry.toJson()).toList()),
  );

  Future<void> _saveReadBookmarks() => _store.setString(
    readBookmarksKey,
    jsonEncode(_readBookmarks.map((media) => media.toJson()).toList()),
  );

  Future<void> _saveReading() => _store.setString(
    continueReadingKey,
    jsonEncode(_continueReading.map((entry) => entry.toJson()).toList()),
  );
}
