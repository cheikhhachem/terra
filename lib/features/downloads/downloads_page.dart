import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/horizontal_edge_fade.dart';
import '../../widgets/terra_header.dart';
import '../library/media_poster_card.dart';
import '../extensions/extension_manager.dart';
import '../extensions/sora_extension_service.dart';
import '../library/library_repository.dart';
import '../player/player_page.dart';
import '../player/player_source.dart';
import '../reading/read_download_repository.dart';
import '../reading/read_reader_page.dart';
import '../reading/reading_models.dart';
import 'download_models.dart';
import 'download_repository.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.readDownloads,
    required this.extensions,
    required this.service,
    required this.library,
  });

  final DownloadRepository downloads;
  final ReadDownloadRepository readDownloads;
  final ExtensionManager extensions;
  final ExtensionService service;
  final LibraryRepository library;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: FTabs(
      expands: true,
      children: [
        FTabEntry(
          label: const Text('Watch'),
          child: ListenableBuilder(
            listenable: downloads,
            builder: (context, _) {
              final pending = downloads.entries
                  .where((entry) => entry.status != DownloadStatus.completed)
                  .toList();
              final groups = _groups(downloads.entries);
              return _DownloadsOverview<DownloadEntry>(
                active: pending,
                groups: groups,
                completedBytes: downloads.completedBytes,
                activeBuilder: (entry) =>
                    _DownloadRow(entry: entry, downloads: downloads),
                onOpenGroup: (group) => _openGroup(context, group, downloads),
                onShowAll: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FinishedDownloadsPage<DownloadEntry>(
                      listenable: downloads,
                      groups: () => _groups(downloads.entries),
                      onOpenGroup: (context, group) =>
                          _openGroup(context, group, downloads),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        FTabEntry(
          label: const Text('Read'),
          child: ListenableBuilder(
            listenable: readDownloads,
            builder: (context, _) {
              final active = readDownloads.entries
                  .where(
                    (entry) => entry.status != ReadDownloadStatus.completed,
                  )
                  .toList();
              final groups = _readGroups(readDownloads.entries);
              return _DownloadsOverview<ReadDownloadEntry>(
                active: active,
                groups: groups,
                completedBytes: readDownloads.completedBytes,
                unit: 'chapter',
                activeBuilder: (entry) => _ReadDownloadRow(
                  entry: entry,
                  downloads: readDownloads,
                  extensions: extensions,
                  service: service,
                ),
                onOpenGroup: (group) => _openReadGroup(
                  context,
                  group,
                  readDownloads,
                  extensions,
                  service,
                  library,
                ),
                onShowAll: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FinishedDownloadsPage<ReadDownloadEntry>(
                      listenable: readDownloads,
                      groups: () => _readGroups(readDownloads.entries),
                      onOpenGroup: (context, group) => _openReadGroup(
                        context,
                        group,
                        readDownloads,
                        extensions,
                        service,
                        library,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _DownloadsOverview<T> extends StatelessWidget {
  const _DownloadsOverview({
    required this.active,
    required this.groups,
    required this.completedBytes,
    required this.activeBuilder,
    required this.onOpenGroup,
    required this.onShowAll,
    this.unit = 'episode',
  });

  final List<T> active;
  final List<_DownloadGroup<T>> groups;
  final int completedBytes;
  final Widget Function(T entry) activeBuilder;
  final void Function(_DownloadGroup<T> group) onOpenGroup;
  final VoidCallback onShowAll;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (active.isEmpty && groups.isEmpty) return const _EmptyDownloads();
    return ListView(
      padding: EdgeInsets.all(compact ? 12 : 16),
      children: [
        _Summary(
          episodes: groups.fold(
            0,
            (total, group) => total + group.entries.length,
          ),
          bytes: completedBytes,
          active: active.length,
          unit: unit,
        ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Active', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...active.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: activeBuilder(entry),
            ),
          ),
        ],
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionHeader(onExpand: onShowAll),
          const SizedBox(height: 10),
          SizedBox(
            height: compact ? 204 : 240,
            child: HorizontalEdgeFade(
              builder: (controller) => ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: compact ? 136 : 165,
                  child: _GroupCard<T>(
                    group: groups[index],
                    onTap: () => onOpenGroup(groups[index]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadDownloadRow extends StatelessWidget {
  const _ReadDownloadRow({
    required this.entry,
    required this.downloads,
    required this.extensions,
    required this.service,
  });
  final ReadDownloadEntry entry;
  final ReadDownloadRepository downloads;
  final ExtensionManager extensions;
  final ExtensionService service;

  @override
  Widget build(BuildContext context) => _DownloadRowShell(
    leading: entry.status == ReadDownloadStatus.downloading
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.error_outline),
    title: Text(entry.media.title),
    subtitle: Text(
      entry.status == ReadDownloadStatus.downloading
          ? '${entry.chapter.title} · Downloading'
          : entry.error ?? 'Download failed',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.status == ReadDownloadStatus.failed)
          IconButton(
            tooltip: 'Retry download',
            onPressed: () async {
              final module = extensions.installed
                  .where((module) => module.id == entry.media.moduleId)
                  .firstOrNull;
              if (module == null) {
                showFToast(
                  context: context,
                  title: Text('${entry.media.sourceName} is not installed.'),
                  alignment: .topRight,
                );
                return;
              }
              try {
                await downloads.retry(entry, module, service);
              } catch (error) {
                if (context.mounted) {
                  showFToast(
                    context: context,
                    title: Text(error.toString()),
                    alignment: .topRight,
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        IconButton(
          tooltip: 'Delete download',
          onPressed: entry.status == ReadDownloadStatus.downloading
              ? null
              : () => downloads.delete(entry),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}

class _DownloadRowShell extends StatelessWidget {
  const _DownloadRowShell({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FCard(
    child: Material(
      color: Colors.transparent,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.episodes,
    required this.bytes,
    required this.active,
    this.unit = 'episode',
  });

  final int episodes;
  final int bytes;
  final int active;
  final String unit;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.offline_pin_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$episodes ${episodes == 1 ? unit : '${unit}s'} · ${_bytes(bytes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (active > 0)
            Text(
              '$active active',
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text('Finished', style: Theme.of(context).textTheme.titleMedium),
      ),
      IconButton(
        tooltip: 'Show all finished downloads',
        onPressed: onExpand,
        icon: const Icon(Icons.arrow_forward),
      ),
    ],
  );
}

class _GroupCard<T> extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});
  final _DownloadGroup<T> group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MediaPosterCard(
    title: group.title,
    subtitle:
        '${group.entries.length} ${group.entries.length == 1 ? group.unit : '${group.unit}s'} · ${_bytes(group.bytes)}',
    secondarySubtitle: '${group.sourceName} · ${group.sourceType}',
    imageUrl: group.imageUrl,
    onTap: onTap,
  );
}

class _FinishedDownloadsPage<T> extends StatelessWidget {
  const _FinishedDownloadsPage({
    required this.listenable,
    required this.groups,
    required this.onOpenGroup,
  });

  final Listenable listenable;
  final List<_DownloadGroup<T>> Function() groups;
  final void Function(BuildContext context, _DownloadGroup<T> group)
  onOpenGroup;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const TerraHeader(title: Text('Finished downloads')),
          Expanded(
            child: ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final values = groups();
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 165,
                    mainAxisExtent: 230,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: values.length,
                  itemBuilder: (context, index) => _GroupCard<T>(
                    group: values[index],
                    onTap: () => onOpenGroup(context, values[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _DownloadedItemPage<T> extends StatefulWidget {
  const _DownloadedItemPage({
    required this.listenable,
    required this.currentGroup,
    required this.rowBuilder,
    required this.deleteAll,
  });

  final Listenable listenable;
  final _DownloadGroup<T>? Function() currentGroup;
  final Widget Function(BuildContext context, T entry) rowBuilder;
  final Future<void> Function(List<T> entries) deleteAll;

  @override
  State<_DownloadedItemPage<T>> createState() => _DownloadedItemPageState<T>();
}

class _DownloadedItemPageState<T> extends State<_DownloadedItemPage<T>> {
  late _DownloadGroup<T> group;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    group = widget.currentGroup()!;
    widget.listenable.addListener(_refresh);
  }

  void _refresh() {
    final next = widget.currentGroup();
    if (next == null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else if (next != null && mounted) {
      setState(() => group = next);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          TerraHeader(
            title: Text(group.title),
            actions: [
              FHeaderAction(
                semanticsTooltip: 'Delete all downloaded ${group.unit}s',
                onPress: () => _deleteGroup(context),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${group.entries.length} ${group.entries.length == 1 ? group.unit : '${group.unit}s'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  _bytes(group.bytes),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: group.entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  widget.rowBuilder(context, group.entries[index]),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _deleteGroup(BuildContext context) async {
    final confirmed =
        await showFDialog<bool>(
          context: context,
          builder: (dialogContext, _, animation) => FDialog(
            animation: animation,
            semanticsLabel: 'Delete all downloaded ${group.unit}s?',
            builder: (_, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete all downloaded ${group.unit}s?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${group.entries.length} local ${group.entries.length == 1 ? group.unit : '${group.unit}s'} will be removed.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FButton(
                        variant: .outline,
                        mainAxisSize: .min,
                        onPress: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FButton(
                        variant: .destructive,
                        mainAxisSize: .min,
                        onPress: () => Navigator.pop(dialogContext, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (!confirmed) return;
    _closing = true;
    widget.listenable.removeListener(_refresh);
    await widget.deleteAll(group.entries);
    if (context.mounted) Navigator.pop(context);
  }
}

class _CompletedEpisodeRow extends StatelessWidget {
  const _CompletedEpisodeRow({required this.entry, required this.downloads});
  final DownloadEntry entry;
  final DownloadRepository downloads;

  @override
  Widget build(BuildContext context) => _DownloadRowShell(
    leading: const Icon(Icons.play_circle_outline),
    title: Text(entry.episodeLabel),
    subtitle: Text(
      'Season ${entry.season} · ${entry.qualityLabel} · ${_bytes(entry.receivedBytes)}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Share episode',
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              files: [XFile(entry.localPath)],
              fileNameOverrides: [_shareName(entry)],
              subject: '${entry.title} · ${entry.episodeLabel}',
            ),
          ),
          icon: const Icon(Icons.share_outlined),
        ),
        IconButton(
          tooltip: 'Delete episode',
          onPressed: () => downloads.delete(entry),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    onTap: () => _play(context, entry),
  );
}

class _CompletedChapterRow extends StatelessWidget {
  const _CompletedChapterRow({
    required this.entry,
    required this.downloads,
    required this.extensions,
    required this.service,
    required this.library,
  });

  final ReadDownloadEntry entry;
  final ReadDownloadRepository downloads;
  final ExtensionManager extensions;
  final ExtensionService service;
  final LibraryRepository library;

  @override
  Widget build(BuildContext context) => _DownloadRowShell(
    leading: const Icon(Icons.auto_stories_outlined),
    title: Text(entry.chapter.title),
    subtitle: Text(
      _bytes(entry.bytes),
      style: Theme.of(context).textTheme.bodySmall,
    ),
    trailing: IconButton(
      tooltip: 'Delete chapter',
      onPressed: () => downloads.delete(entry),
      icon: const Icon(Icons.delete_outline),
    ),
    onTap: () =>
        _openRead(context, entry, downloads, extensions, service, library),
  );
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.entry, required this.downloads});
  final DownloadEntry entry;
  final DownloadRepository downloads;

  @override
  Widget build(BuildContext context) => _DownloadRowShell(
    leading: const Icon(Icons.downloading),
    title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.episodeLabel} · ${entry.qualityLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (entry.status == DownloadStatus.downloading) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: entry.progress == 0 ? null : entry.progress,
          ),
        ] else if (entry.status == DownloadStatus.queued)
          Text(
            downloads.wifiOnly
                ? 'Waiting for Wi-Fi or an available slot'
                : 'Waiting for an available slot',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Text(
            entry.error ?? 'Download cancelled',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: entry.status == DownloadStatus.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
      ],
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.status == DownloadStatus.downloading)
          IconButton(
            tooltip: 'Cancel download',
            onPressed: () => downloads.cancel(entry.id),
            icon: const Icon(Icons.close),
          )
        else
          IconButton(
            tooltip: 'Retry download',
            onPressed: () => downloads.retry(entry),
            icon: const Icon(Icons.refresh),
          ),
        IconButton(
          tooltip: 'Delete download',
          onPressed: () => downloads.delete(entry),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_for_offline_outlined, size: 48),
          SizedBox(height: 16),
          Text('Nothing downloaded'),
          SizedBox(height: 6),
          Text('Download episodes or chapters from their details page.'),
        ],
      ),
    ),
  );
}

class _DownloadGroup<T> {
  const _DownloadGroup({
    required this.mediaId,
    required this.entries,
    required this.title,
    required this.imageUrl,
    required this.sourceName,
    required this.sourceType,
    required this.bytes,
    required this.createdAt,
    required this.unit,
  });

  final String mediaId;
  final List<T> entries;
  final String title;
  final String imageUrl;
  final String sourceName;
  final String sourceType;
  final int bytes;
  final DateTime createdAt;
  final String unit;
}

List<_DownloadGroup<DownloadEntry>> _groups(List<DownloadEntry> entries) {
  final values = <String, List<DownloadEntry>>{};
  for (final entry in entries.where(
    (entry) => entry.status == DownloadStatus.completed,
  )) {
    values.putIfAbsent(entry.mediaId, () => []).add(entry);
  }
  final groups = <_DownloadGroup<DownloadEntry>>[];
  for (final value in values.entries) {
    value.value.sort((a, b) {
      final season = a.season.compareTo(b.season);
      return season != 0 ? season : a.episodeNumber.compareTo(b.episodeNumber);
    });
    final first = value.value.first;
    groups.add(
      _DownloadGroup(
        mediaId: value.key,
        entries: value.value,
        title: first.title,
        imageUrl: value.value
            .map((entry) => entry.posterPath)
            .firstWhere(
              (path) => path.isNotEmpty,
              orElse: () => first.imageUrl,
            ),
        sourceName: first.sourceName,
        sourceType: first.sourceType,
        bytes: value.value.fold(
          0,
          (total, entry) => total + entry.receivedBytes,
        ),
        createdAt: value.value
            .map((entry) => entry.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        unit: 'episode',
      ),
    );
  }
  groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return groups;
}

List<_DownloadGroup<ReadDownloadEntry>> _readGroups(
  List<ReadDownloadEntry> entries,
) {
  final values = <String, List<ReadDownloadEntry>>{};
  for (final entry in entries.where(
    (entry) => entry.status == ReadDownloadStatus.completed,
  )) {
    values.putIfAbsent(entry.media.id, () => []).add(entry);
  }
  final groups = <_DownloadGroup<ReadDownloadEntry>>[];
  for (final value in values.entries) {
    value.value.sort((a, b) {
      final chapter = a.chapter.number.compareTo(b.chapter.number);
      return chapter != 0
          ? chapter
          : a.chapter.title.compareTo(b.chapter.title);
    });
    final first = value.value.first;
    groups.add(
      _DownloadGroup(
        mediaId: value.key,
        entries: value.value,
        title: first.media.title,
        imageUrl: first.media.imageUrl,
        sourceName: first.media.sourceName,
        sourceType: switch (first.media.kind) {
          ReadMediaKind.manga => 'Manga',
          ReadMediaKind.novel => 'Novel',
        },
        bytes: value.value.fold(0, (total, entry) => total + entry.bytes),
        createdAt: value.value
            .map((entry) => entry.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        unit: 'chapter',
      ),
    );
  }
  groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return groups;
}

void _openGroup(
  BuildContext context,
  _DownloadGroup<DownloadEntry> group,
  DownloadRepository downloads,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _DownloadedItemPage<DownloadEntry>(
      listenable: downloads,
      currentGroup: () => _groups(
        downloads.entries,
      ).where((item) => item.mediaId == group.mediaId).firstOrNull,
      rowBuilder: (context, entry) =>
          _CompletedEpisodeRow(entry: entry, downloads: downloads),
      deleteAll: downloads.deleteAll,
    ),
  ),
);

void _openReadGroup(
  BuildContext context,
  _DownloadGroup<ReadDownloadEntry> group,
  ReadDownloadRepository downloads,
  ExtensionManager extensions,
  ExtensionService service,
  LibraryRepository library,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _DownloadedItemPage<ReadDownloadEntry>(
      listenable: downloads,
      currentGroup: () => _readGroups(
        downloads.entries,
      ).where((item) => item.mediaId == group.mediaId).firstOrNull,
      rowBuilder: (context, entry) => _CompletedChapterRow(
        entry: entry,
        downloads: downloads,
        extensions: extensions,
        service: service,
        library: library,
      ),
      deleteAll: (entries) async {
        for (final entry in entries) {
          await downloads.delete(entry);
        }
      },
    ),
  ),
);

void _openRead(
  BuildContext context,
  ReadDownloadEntry entry,
  ReadDownloadRepository downloads,
  ExtensionManager extensions,
  ExtensionService service,
  LibraryRepository library,
) {
  final module = extensions.installed
      .where((module) => module.id == entry.media.moduleId)
      .firstOrNull;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReadReaderPage(
        module: module,
        media: entry.media,
        chapters: [entry.chapter],
        chapterIndex: 0,
        service: service,
        library: library,
        downloads: downloads,
        download: entry,
      ),
    ),
  );
}

void _play(BuildContext context, DownloadEntry entry) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          source: PlayerSource(
            title: entry.title,
            episodeLabel: entry.episodeLabel,
            resumeKey: 'download:${entry.id}',
            qualities: [
              PlayerQuality(label: entry.qualityLabel, url: entry.localPath),
            ],
          ),
        ),
      ),
    );

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _shareName(DownloadEntry entry) {
  final extension = entry.localPath.split('.').last;
  final name = '${entry.title} - ${entry.episodeLabel}'
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${name.isEmpty ? 'Terra episode' : name}.$extension';
}
