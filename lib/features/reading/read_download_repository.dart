import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extensions/models.dart';
import '../extensions/sora_extension_service.dart';
import 'reading_models.dart';

enum ReadDownloadStatus { downloading, completed, failed }

class ReadDownloadEntry {
  const ReadDownloadEntry({
    required this.id,
    required this.media,
    required this.chapter,
    required this.chapterIndex,
    required this.status,
    required this.createdAt,
    this.paths = const [],
    this.error,
  });

  final String id;
  final ReadMedia media;
  final ReadChapter chapter;
  final int chapterIndex;
  final ReadDownloadStatus status;
  final DateTime createdAt;
  final List<String> paths;
  final String? error;

  int get bytes => paths.fold(0, (total, path) {
    try {
      return total + File(path).lengthSync();
    } on FileSystemException {
      return total;
    }
  });

  ReadDownloadEntry copyWith({
    ReadDownloadStatus? status,
    List<String>? paths,
    String? error,
  }) => ReadDownloadEntry(
    id: id,
    media: media,
    chapter: chapter,
    chapterIndex: chapterIndex,
    status: status ?? this.status,
    createdAt: createdAt,
    paths: paths ?? this.paths,
    error: error,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'media': media.toJson(),
    'chapter': {
      'href': chapter.href,
      'title': chapter.title,
      'number': chapter.number,
      'dateUpload': chapter.dateUpload,
      'scanlator': chapter.scanlator,
    },
    'chapterIndex': chapterIndex,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'paths': paths,
    'error': error,
  };

  static ReadDownloadEntry? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final media = ReadMedia.tryFromJson(json['media']);
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final status = ReadDownloadStatus.values
        .where((status) => status.name == json['status'])
        .firstOrNull;
    final chapterIndex = (json['chapterIndex'] as num?)?.toInt();
    if (media == null ||
        createdAt == null ||
        status == null ||
        chapterIndex == null) {
      return null;
    }
    final chapter = ReadChapter.fromJson(json['chapter'], chapterIndex);
    return ReadDownloadEntry(
      id: json['id']?.toString() ?? '',
      media: media,
      chapter: chapter,
      chapterIndex: chapterIndex,
      status: status == ReadDownloadStatus.downloading
          ? ReadDownloadStatus.failed
          : status,
      createdAt: createdAt,
      paths: (json['paths'] as List? ?? const [])
          .map((path) => path.toString())
          .toList(),
      error: status == ReadDownloadStatus.downloading
          ? 'Download was interrupted.'
          : json['error']?.toString(),
    );
  }
}

class ReadDownloadRepository extends ChangeNotifier {
  static const _key = 'terra.read.downloads.v1';
  final List<ReadDownloadEntry> _entries = [];
  bool initialized = false;
  bool _disposed = false;

  List<ReadDownloadEntry> get entries => List.unmodifiable(_entries);
  int get completedBytes => _entries
      .where((entry) => entry.status == ReadDownloadStatus.completed)
      .fold(0, (total, entry) => total + entry.bytes);

  Future<void> initialize() async {
    if (initialized) return;
    try {
      final value = jsonDecode(
        await SharedPreferencesAsync().getString(_key) ?? '[]',
      );
      if (value is List) {
        _entries.addAll(value.map(ReadDownloadEntry.tryFromJson).nonNulls);
      }
    } on FormatException {
      _entries.clear();
    }
    _sort();
    initialized = true;
    _notify();
    await _save();
  }

  bool contains(String id) => _entries.any(
    (entry) => entry.id == id && entry.status != ReadDownloadStatus.failed,
  );

  ReadDownloadEntry? completed(String id) => _entries
      .where(
        (entry) =>
            entry.id == id && entry.status == ReadDownloadStatus.completed,
      )
      .firstOrNull;

  Future<void> add({
    required InstalledSoraModule module,
    required ReadMedia media,
    required ReadChapter chapter,
    required int chapterIndex,
    required ExtensionService service,
  }) async {
    final id = '${module.id}:${chapter.href}';
    if (contains(id)) throw StateError('This chapter is already saved.');
    _entries.removeWhere((entry) => entry.id == id);
    var entry = ReadDownloadEntry(
      id: id,
      media: media,
      chapter: chapter,
      chapterIndex: chapterIndex,
      status: ReadDownloadStatus.downloading,
      createdAt: DateTime.now(),
    );
    _entries.add(entry);
    _sort();
    _notify();
    await _save();
    Directory? downloadDirectory;
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(
        '${root.path}/read_downloads/${_safe(module.id)}/${_safe(id)}',
      );
      downloadDirectory = directory;
      await directory.create(recursive: true);
      final paths = <String>[];
      if (media.kind == ReadMediaKind.novel) {
        final html = await service.readText(module, chapter);
        if (html.trim().isEmpty) {
          throw StateError('The source returned no chapter text.');
        }
        final file = File('${directory.path}/chapter.html');
        await file.writeAsString(html, flush: true);
        paths.add(file.path);
      } else {
        final pages = await service.readPages(module, chapter);
        if (pages.isEmpty) throw StateError('The source returned no pages.');
        for (final (index, page) in pages.indexed) {
          final file = File(
            '${directory.path}/${index + 1}.${_extension(page.url)}',
          );
          await _download(page, file);
          paths.add(file.path);
        }
      }
      entry = entry.copyWith(
        status: ReadDownloadStatus.completed,
        paths: paths,
      );
    } catch (error) {
      if (downloadDirectory != null && await downloadDirectory.exists()) {
        await downloadDirectory.delete(recursive: true);
      }
      entry = entry.copyWith(
        status: ReadDownloadStatus.failed,
        error: error.toString(),
      );
    }
    _replace(entry);
    _notify();
    await _save();
    if (entry.status == ReadDownloadStatus.failed) {
      throw StateError(entry.error ?? 'Download failed.');
    }
  }

  Future<void> retry(
    ReadDownloadEntry entry,
    InstalledSoraModule module,
    ExtensionService service,
  ) async {
    await delete(entry);
    await add(
      module: module,
      media: entry.media,
      chapter: entry.chapter,
      chapterIndex: entry.chapterIndex,
      service: service,
    );
  }

  Future<void> delete(ReadDownloadEntry entry) async {
    for (final path in entry.paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (entry.paths.isNotEmpty) {
      final directory = File(entry.paths.first).parent;
      if (await directory.exists()) await directory.delete(recursive: true);
    } else {
      final directory = await _directoryFor(entry.media.moduleId, entry.id);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    _entries.removeWhere((item) => item.id == entry.id);
    _notify();
    await _save();
  }

  Future<void> _download(ReadPage page, File file) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(page.url));
      page.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse(page.url),
        );
      }
      await response.pipe(file.openWrite());
    } finally {
      client.close(force: true);
    }
  }

  void _replace(ReadDownloadEntry entry) {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index >= 0) _entries[index] = entry;
    _sort();
  }

  void _sort() => _entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _save() => SharedPreferencesAsync().setString(
    _key,
    jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
  );

  Future<Directory> _directoryFor(String moduleId, String id) async {
    final root = await getApplicationSupportDirectory();
    return Directory(
      '${root.path}/read_downloads/${_safe(moduleId)}/${_safe(id)}',
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _safe(String value) => value.hashCode.toUnsigned(32).toRadixString(16);

String _extension(String url) {
  final extension = Uri.tryParse(url)?.pathSegments.lastOrNull?.split('.').last;
  return extension != null && RegExp(r'^[a-zA-Z0-9]{2,5}$').hasMatch(extension)
      ? extension.toLowerCase()
      : 'jpg';
}
