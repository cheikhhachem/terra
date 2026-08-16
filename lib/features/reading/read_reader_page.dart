import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../extensions/models.dart';
import '../extensions/sora_extension_service.dart';
import '../library/library_repository.dart';
import 'mangayomi_manga_reader.dart';
import 'mangayomi_novel_reader.dart';
import 'mangayomi_reader_settings.dart';
import 'read_download_repository.dart';
import 'reading_models.dart';

class ReadReaderPage extends StatefulWidget {
  const ReadReaderPage({
    super.key,
    required this.module,
    required this.media,
    required this.chapters,
    required this.chapterIndex,
    required this.service,
    required this.library,
    required this.downloads,
    this.download,
  });

  final InstalledSoraModule? module;
  final ReadMedia media;
  final List<ReadChapter> chapters;
  final int chapterIndex;
  final ExtensionService service;
  final LibraryRepository library;
  final ReadDownloadRepository downloads;
  final ReadDownloadEntry? download;

  @override
  State<ReadReaderPage> createState() => _ReadReaderPageState();
}

class _ReadReaderPageState extends State<ReadReaderPage> {
  late int _chapterIndex = widget.chapterIndex;
  late Future<Object> _content;
  final MangayomiReaderSettings _settings = MangayomiReaderSettings();
  Timer? _progressTimer;
  bool _settingsReady = false;
  double _initialProgress = 0;
  double? _lastProgress;

  ReadChapter get _chapter => widget.chapters[_chapterIndex];
  int get _progressChapterIndex =>
      widget.download != null && widget.chapters.length == 1
      ? widget.download!.chapterIndex
      : _chapterIndex;
  ReadDownloadEntry? get _download {
    if (widget.download?.chapter.href == _chapter.href) return widget.download;
    return widget.downloads.completed(
      '${widget.media.moduleId}:${_chapter.href}',
    );
  }

  @override
  void initState() {
    super.initState();
    _initialProgress = _storedProgress();
    _loadContent();
    _settings.load().then((_) {
      if (mounted) setState(() => _settingsReady = true);
    });
  }

  double _storedProgress() =>
      widget.library.continueReading
          .where(
            (entry) =>
                entry.media.id == widget.media.id &&
                entry.chapterHref == _chapter.href,
          )
          .firstOrNull
          ?.position ??
      0;

  void _loadContent() {
    if (widget.media.kind == ReadMediaKind.manga) {
      _content = _download == null
          ? widget.service.readPages(widget.module!, _chapter)
          : Future.value(
              _download!.paths
                  .map((path) => ReadPage(url: Uri.file(path).toString()))
                  .toList(),
            );
    } else {
      _content = _download == null
          ? widget.service.readText(widget.module!, _chapter)
          : Future.sync(() {
              if (_download!.paths.length != 1) {
                throw StateError('The downloaded novel chapter is incomplete.');
              }
              return File(_download!.paths.single).readAsString();
            }).then((value) => value);
    }
  }

  void _scheduleProgress(double progress) {
    _lastProgress = progress.clamp(0, 1);
    _progressTimer?.cancel();
    _progressTimer = Timer(
      const Duration(milliseconds: 350),
      () => _saveProgress(_lastProgress!),
    );
  }

  Future<void> _saveProgress(double progress) =>
      widget.library.updateReadingProgress(
        media: widget.media,
        chapter: _chapter,
        chapterIndex: _progressChapterIndex,
        position: progress,
      );

  void _goToChapter(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    _flushProgress();
    setState(() {
      _chapterIndex = index;
      _lastProgress = null;
      _initialProgress = _storedProgress();
      _loadContent();
    });
  }

  void _flushProgress() {
    _progressTimer?.cancel();
    if (_lastProgress case final progress?) unawaited(_saveProgress(progress));
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    if (_lastProgress case final progress?) {
      final library = widget.library;
      final media = widget.media;
      final chapter = _chapter;
      final chapterIndex = _progressChapterIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          library.updateReadingProgress(
            media: media,
            chapter: chapter,
            chapterIndex: chapterIndex,
            position: progress,
          ),
        );
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return FutureBuilder<Object>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ReaderError(error: snapshot.error!, retry: _retry);
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.media.kind == ReadMediaKind.manga) {
          final pages = snapshot.data! as List<ReadPage>;
          if (pages.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('The source returned no pages.')),
            );
          }
          return MangayomiMangaReader(
            key: ValueKey(_chapter.href),
            title: widget.media.title,
            chapterTitle: _chapter.title,
            pages: pages,
            settings: _settings,
            initialProgress: _initialProgress,
            onProgress: _scheduleProgress,
            onPreviousChapter: _chapterIndex > 0
                ? () => _goToChapter(_chapterIndex - 1)
                : null,
            onNextChapter: _chapterIndex + 1 < widget.chapters.length
                ? () => _goToChapter(_chapterIndex + 1)
                : null,
            onChapterList: _showChapterList,
          );
        }
        final html = snapshot.data! as String;
        if (html.trim().isEmpty) {
          return const Scaffold(
            body: Center(child: Text('The source returned no chapter text.')),
          );
        }
        return MangayomiNovelReader(
          key: ValueKey(_chapter.href),
          title: widget.media.title,
          chapterTitle: _chapter.title,
          html: _sanitize(html),
          settings: _settings,
          initialProgress: _initialProgress,
          onProgress: _scheduleProgress,
          onPreviousChapter: _chapterIndex > 0
              ? () => _goToChapter(_chapterIndex - 1)
              : null,
          onNextChapter: _chapterIndex + 1 < widget.chapters.length
              ? () => _goToChapter(_chapterIndex + 1)
              : null,
          onChapterList: _showChapterList,
        );
      },
    );
  }

  void _retry() => setState(_loadContent);

  Future<void> _showChapterList() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.media.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.chapters.length,
                itemBuilder: (_, index) => ListTile(
                  selected: index == _chapterIndex,
                  leading: index == _chapterIndex
                      ? const Icon(Icons.menu_book)
                      : const Icon(Icons.article_outlined),
                  title: Text(widget.chapters[index].title),
                  subtitle: widget.chapters[index].scanlator.isEmpty
                      ? null
                      : Text(widget.chapters[index].scanlator),
                  onTap: () => Navigator.pop(context, index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != _chapterIndex) _goToChapter(selected);
  }
}

String _sanitize(String html) => html
    .replaceAll(
      RegExp(
        r'<(script|iframe|object)[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    )
    .replaceAll(
      RegExp(r'''\son\w+\s*=\s*(["']).*?\1''', caseSensitive: false),
      '',
    );

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FButton(onPress: retry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}
