import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../widgets/media_detail_layout.dart';
import '../extensions/models.dart';
import '../extensions/sora_extension_service.dart';
import '../library/library_repository.dart';
import 'read_download_repository.dart';
import 'read_reader_page.dart';
import 'reading_models.dart';

class ReadDetailPage extends StatefulWidget {
  const ReadDetailPage({
    super.key,
    required this.module,
    required this.result,
    required this.service,
    required this.library,
    required this.downloads,
  });

  final InstalledSoraModule module;
  final ReadSearchResult result;
  final ExtensionService service;
  final LibraryRepository library;
  final ReadDownloadRepository downloads;

  @override
  State<ReadDetailPage> createState() => _ReadDetailPageState();
}

class _ReadDetailPageState extends State<ReadDetailPage> {
  late Future<ReadDetails> _details = _load();
  bool _refreshing = false;
  bool _ascending = true;

  ReadMedia get _media => ReadMedia(
    id: 'read:${widget.module.id}:${widget.result.href}',
    moduleId: widget.module.id,
    sourceName: widget.module.metadata.sourceName,
    title: widget.result.title,
    imageUrl: widget.result.imageUrl,
    detailHref: widget.result.href,
    kind: widget.service.readKind(widget.module),
    addedAt: DateTime.now(),
  );

  Future<ReadDetails> _load() =>
      widget.service.readDetails(widget.module, widget.result.href);

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _details = _load();
    });
    try {
      await _details;
    } catch (_) {
      // The FutureBuilder renders refresh failures.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          MediaDetailHeader(
            title: widget.result.title,
            refreshTooltip: 'Refresh chapters',
            refreshing: _refreshing,
            onRefresh: _refresh,
            bookmarks: widget.library,
            isBookmarked: () => widget.library.containsRead(_media.id),
            onBookmark: () => widget.library.toggleRead(_media),
          ),
          Expanded(
            child: FutureBuilder<ReadDetails>(
              future: _details,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _DetailError(error: snapshot.error!, retry: _refresh);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(snapshot.data!);
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _content(ReadDetails details) {
    final chapters = details.chapters.indexed.toList()
      ..sort((a, b) {
        final result = a.$2.number.compareTo(b.$2.number);
        if (result != 0) return _ascending ? result : -result;
        return a.$1.compareTo(b.$1);
      });
    return MediaDetailContent<ReadChapter>(
      title: widget.result.title,
      posterUrl: widget.result.imageUrl,
      posterFallbackIcon: Icons.auto_stories_outlined,
      metadata: [
        widget.module.metadata.sourceName,
        if (details.author.isNotEmpty) 'By ${details.author}',
        if (details.artist.isNotEmpty) 'Art: ${details.artist}',
        details.status,
        if (details.genres.isNotEmpty) details.genres.join(' · '),
      ],
      description: details.description,
      sectionTitle: 'Chapters',
      groups: [
        MediaDetailGroup<ReadChapter>(
          label: 'Chapters',
          value: 'chapters',
          items: [
            for (final chapter in chapters)
              (item: chapter.$2, originalIndex: chapter.$1),
          ],
        ),
      ],
      selectedGroup: 'chapters',
      onGroupChanged: (_) {},
      ascending: _ascending,
      onSort: () => setState(() => _ascending = !_ascending),
      sortAscendingTooltip: 'Sort chapters ascending',
      sortDescendingTooltip: 'Sort chapters descending',
      emptyMessage: 'This source returned no chapters.',
      itemBuilder: (context, chapter, index) => _ChapterTile(
        module: widget.module,
        media: _media,
        chapter: chapter,
        index: index,
        chapters: details.chapters,
        service: widget.service,
        library: widget.library,
        downloads: widget.downloads,
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.module,
    required this.media,
    required this.chapter,
    required this.index,
    required this.chapters,
    required this.service,
    required this.library,
    required this.downloads,
  });

  final InstalledSoraModule module;
  final ReadMedia media;
  final ReadChapter chapter;
  final int index;
  final List<ReadChapter> chapters;
  final ExtensionService service;
  final LibraryRepository library;
  final ReadDownloadRepository downloads;

  String get _downloadId => '${module.id}:${chapter.href}';

  @override
  Widget build(BuildContext context) => MediaDetailItem(
    leading: Icon(
      media.kind == ReadMediaKind.novel
          ? Icons.subject
          : Icons.photo_library_outlined,
    ),
    title: Text(chapter.title),
    subtitle:
        [
          chapter.scanlator,
          chapter.dateUpload,
        ].where((value) => value.isNotEmpty).isEmpty
        ? null
        : Text(
            [
              chapter.scanlator,
              chapter.dateUpload,
            ].where((value) => value.isNotEmpty).join(' · '),
          ),
    actions: [
      ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final entry = downloads.entries
              .where((entry) => entry.id == _downloadId)
              .firstOrNull;
          return IconButton(
            tooltip: switch (entry?.status) {
              ReadDownloadStatus.downloading => 'Downloading chapter',
              ReadDownloadStatus.completed => 'Chapter downloaded',
              ReadDownloadStatus.failed => 'Retry download',
              null => 'Download chapter',
            },
            onPressed: entry?.status == ReadDownloadStatus.downloading
                ? null
                : () => _download(context, entry),
            icon: switch (entry?.status) {
              ReadDownloadStatus.downloading => const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              ReadDownloadStatus.completed => const Icon(Icons.download_done),
              ReadDownloadStatus.failed => const Icon(Icons.refresh),
              null => const Icon(Icons.download_outlined),
            },
          );
        },
      ),
    ],
    onOpen: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadReaderPage(
          module: module,
          media: media,
          chapters: chapters,
          chapterIndex: index,
          service: service,
          library: library,
          downloads: downloads,
          download: downloads.completed(_downloadId),
        ),
      ),
    ),
  );

  Future<void> _download(
    BuildContext context,
    ReadDownloadEntry? existing,
  ) async {
    try {
      if (existing == null) {
        await downloads.add(
          module: module,
          media: media,
          chapter: chapter,
          chapterIndex: index,
          service: service,
        );
      } else {
        await downloads.retry(existing, module, service);
      }
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Chapter downloaded'),
          alignment: .topRight,
        );
      }
    } catch (error) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: Text(error.toString()),
          alignment: .topRight,
        );
      }
    }
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
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
  );
}
