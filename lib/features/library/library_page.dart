import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../widgets/terra_header.dart';
import '../../widgets/horizontal_edge_fade.dart';
import '../downloads/download_repository.dart';
import '../extensions/extension_detail_page.dart';
import '../extensions/extension_detail_repository.dart';
import '../extensions/extension_manager.dart';
import '../extensions/extension_navigation.dart';
import '../extensions/models.dart';
import '../extensions/sora_extension_service.dart';
import '../reading/read_detail_page.dart';
import '../reading/read_download_repository.dart';
import '../reading/read_reader_page.dart';
import '../reading/reading_models.dart';
import 'library_models.dart';
import 'library_repository.dart';
import 'media_poster_card.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    required this.library,
    required this.extensions,
    required this.service,
    required this.details,
    required this.downloads,
    required this.readDownloads,
  });

  final LibraryRepository library;
  final ExtensionManager extensions;
  final ExtensionService service;
  final ExtensionDetailRepository details;
  final DownloadRepository downloads;
  final ReadDownloadRepository readDownloads;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: FTabs(
      expands: true,
      children: [
        FTabEntry(
          label: const Text('Watch'),
          child: _LibraryTab<ContinueWatchingEntry, LibraryMedia>(
            listenable: library,
            first: _LibrarySectionSpec(
              title: 'Continue Watching',
              emptyIcon: Icons.play_circle_outline,
              emptyText: 'Start an episode and your progress will appear here.',
              itemGetter: () => library.continueWatching,
              cardAdapter: (entry) => (
                title: entry.media.title,
                subtitle: '${entry.episodeLabel} · ${entry.media.sourceName}',
                imageUrl: entry.media.imageUrl,
                progress: entry.progress,
              ),
              onTap: (entry) => _resume(context, entry),
            ),
            second: _LibrarySectionSpec(
              title: 'My Library',
              emptyIcon: Icons.bookmark_border,
              emptyText: 'Bookmark media from search or an episodes page.',
              itemGetter: () => library.bookmarks,
              cardAdapter: (media) => (
                title: media.title,
                subtitle: media.sourceName,
                imageUrl: media.imageUrl,
                progress: null,
              ),
              onTap: (media) => _openMedia(context, media),
              onRemove: (media) => library.remove(media.id),
            ),
          ),
        ),
        FTabEntry(
          label: const Text('Read'),
          child: _LibraryTab<ContinueReadingEntry, ReadMedia>(
            listenable: library,
            first: _LibrarySectionSpec(
              title: 'Continue Reading',
              emptyIcon: Icons.menu_book_outlined,
              emptyText:
                  'Start a chapter and your reading progress will appear here.',
              itemGetter: () => library.continueReading,
              cardAdapter: (entry) => (
                title: entry.media.title,
                subtitle: '${entry.chapterTitle} · ${entry.media.sourceName}',
                imageUrl: entry.media.imageUrl,
                progress: entry.position,
              ),
              onTap: (entry) => _resumeRead(context, entry),
            ),
            second: _LibrarySectionSpec(
              title: 'My Library',
              emptyIcon: Icons.bookmark_border,
              emptyText:
                  'Saved manga, webtoons, books, and novels will appear here.',
              itemGetter: () => library.readBookmarks,
              cardAdapter: (media) => (
                title: media.title,
                subtitle: media.sourceName,
                imageUrl: media.imageUrl,
                progress: null,
              ),
              onTap: (media) => _openRead(context, media),
              onRemove: (media) => library.removeRead(media.id),
            ),
          ),
        ),
      ],
    ),
  );

  InstalledSoraModule? _module(String id) {
    for (final module in extensions.installed) {
      if (module.id == id) return module;
    }
    return null;
  }

  Future<void> _openMedia(BuildContext context, LibraryMedia media) async {
    final module = _module(media.moduleId);
    if (module == null) {
      _missingModule(context, media.sourceName);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExtensionDetailPage(
          module: module,
          result: SoraSearchResult(
            title: media.title,
            imageUrl: media.imageUrl,
            href: media.detailHref,
          ),
          service: service,
          details: details,
          library: library,
          downloads: downloads,
        ),
      ),
    );
  }

  Future<void> _resume(
    BuildContext context,
    ContinueWatchingEntry entry,
  ) async {
    final module = _module(entry.media.moduleId);
    if (module == null) {
      _missingModule(context, entry.media.sourceName);
      return;
    }
    try {
      await resumeExtensionEntry(
        context: context,
        module: module,
        entry: entry,
        service: service,
        details: details,
        library: library,
        downloads: downloads,
      );
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

  Future<void> _openRead(BuildContext context, ReadMedia media) async {
    final module = _module(media.moduleId);
    if (module == null) {
      _missingModule(context, media.sourceName);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadDetailPage(
          module: module,
          result: ReadSearchResult(
            title: media.title,
            href: media.detailHref,
            imageUrl: media.imageUrl,
          ),
          service: service,
          library: library,
          downloads: readDownloads,
        ),
      ),
    );
  }

  Future<void> _resumeRead(
    BuildContext context,
    ContinueReadingEntry entry,
  ) async {
    final module = _module(entry.media.moduleId);
    final local = readDownloads.completed(
      '${entry.media.moduleId}:${entry.chapterHref}',
    );
    if (local != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReadReaderPage(
            module: module,
            media: entry.media,
            chapters: [local.chapter],
            chapterIndex: 0,
            service: service,
            library: library,
            downloads: readDownloads,
            download: local,
          ),
        ),
      );
      return;
    }
    if (module == null) {
      _missingModule(context, entry.media.sourceName);
      return;
    }
    try {
      final readDetails = await service.readDetails(
        module,
        entry.media.detailHref,
      );
      if (!context.mounted) return;
      if (readDetails.chapters.isEmpty) {
        throw StateError('This source returned no chapters.');
      }
      var index = readDetails.chapters.indexWhere(
        (chapter) => chapter.href == entry.chapterHref,
      );
      if (index < 0) {
        index = entry.chapterIndex.clamp(0, readDetails.chapters.length - 1);
      }
      final id = '${module.id}:${readDetails.chapters[index].href}';
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReadReaderPage(
            module: module,
            media: entry.media,
            chapters: readDetails.chapters,
            chapterIndex: index,
            service: service,
            library: library,
            downloads: readDownloads,
            download: readDownloads.completed(id),
          ),
        ),
      );
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

  void _missingModule(BuildContext context, String sourceName) {
    showFToast(
      context: context,
      title: Text(
        '$sourceName is no longer installed. Reinstall it to open this item.',
      ),
      alignment: .topRight,
    );
  }
}

typedef _LibraryCardData = ({
  String title,
  String subtitle,
  String imageUrl,
  double? progress,
});

class _LibrarySectionSpec<T> {
  const _LibrarySectionSpec({
    required this.title,
    required this.emptyIcon,
    required this.emptyText,
    required this.itemGetter,
    required this.cardAdapter,
    required this.onTap,
    this.onRemove,
  });

  final String title;
  final IconData emptyIcon;
  final String emptyText;
  final List<T> Function() itemGetter;
  final _LibraryCardData Function(T item) cardAdapter;
  final ValueChanged<T> onTap;
  final ValueChanged<T>? onRemove;
}

class _LibraryTab<A, B> extends StatelessWidget {
  const _LibraryTab({
    required this.listenable,
    required this.first,
    required this.second,
  });

  final Listenable listenable;
  final _LibrarySectionSpec<A> first;
  final _LibrarySectionSpec<B> second;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => ListView(
        padding: EdgeInsets.all(compact ? 12 : 16),
        children: [
          _LibrarySection(
            listenable: listenable,
            spec: first,
            cardWidth: compact ? 136 : 165,
            cardHeight: compact ? 204 : 240,
          ),
          const SizedBox(height: 30),
          _LibrarySection(
            listenable: listenable,
            spec: second,
            cardWidth: compact ? 136 : 165,
            cardHeight: compact ? 204 : 240,
          ),
        ],
      ),
    );
  }
}

class _LibrarySection<T> extends StatelessWidget {
  const _LibrarySection({
    required this.listenable,
    required this.spec,
    required this.cardWidth,
    required this.cardHeight,
  });

  final Listenable listenable;
  final _LibrarySectionSpec<T> spec;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final items = spec.itemGetter();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                spec.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Show all',
              onPressed: items.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ExpandedLibrarySectionPage(
                          listenable: listenable,
                          spec: spec,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _EmptySection(icon: spec.emptyIcon, text: spec.emptyText)
        else
          SizedBox(
            height: cardHeight,
            child: HorizontalEdgeFade(
              builder: (controller) => ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, index) {
                  final item = items[index];
                  return SizedBox(
                    width: cardWidth,
                    child: _LibraryPosterCard(
                      data: spec.cardAdapter(item),
                      onTap: () => spec.onTap(item),
                      onRemove: spec.onRemove == null
                          ? null
                          : () => spec.onRemove!(item),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandedLibrarySectionPage<T> extends StatelessWidget {
  const _ExpandedLibrarySectionPage({
    required this.listenable,
    required this.spec,
  });

  final Listenable listenable;
  final _LibrarySectionSpec<T> spec;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          TerraHeader(title: Text(spec.title)),
          Expanded(
            child: ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final items = spec.itemGetter();
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 250,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return _LibraryPosterCard(
                      data: spec.cardAdapter(item),
                      onTap: () => spec.onTap(item),
                      onRemove: spec.onRemove == null
                          ? null
                          : () => spec.onRemove!(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _LibraryPosterCard extends StatelessWidget {
  const _LibraryPosterCard({
    required this.data,
    required this.onTap,
    this.onRemove,
  });

  final _LibraryCardData data;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => MediaPosterCard(
    title: data.title,
    subtitle: data.subtitle,
    imageUrl: data.imageUrl,
    progress: data.progress,
    onTap: onTap,
    action: onRemove == null
        ? null
        : IconButton.filledTonal(
            tooltip: 'Remove from library',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: const Icon(Icons.bookmark),
          ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 32),
        const SizedBox(width: 16),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
