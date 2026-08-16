// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../downloads/download_models.dart';
import '../downloads/download_repository.dart';
import '../library/library_repository.dart';
import '../../widgets/media_detail_layout.dart';
import '../../widgets/terra_network_image.dart';
import '../../widgets/episode_operation_overlay.dart';
import 'extension_detail_repository.dart';
import 'extension_navigation.dart';
import 'models.dart';
import 'sora_extension_service.dart';

class ExtensionDetailPage extends StatefulWidget {
  const ExtensionDetailPage({
    super.key,
    required this.module,
    required this.result,
    required this.service,
    required this.details,
    required this.library,
    required this.downloads,
  });
  final InstalledSoraModule module;
  final SoraSearchResult result;
  final ExtensionService service;
  final ExtensionDetailRepository details;
  final LibraryRepository library;
  final DownloadRepository downloads;

  @override
  State<ExtensionDetailPage> createState() => _ExtensionDetailPageState();
}

class _ExtensionDetailPageState extends State<ExtensionDetailPage> {
  SoraDetails? _details;
  List<SoraEpisode> _episodes = const [];
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  int? _season;
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await widget.details.read(widget.module, widget.result.href);
    if (cached != null && mounted) {
      _apply(cached);
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
    await _refresh(blocking: cached == null);
  }

  Future<void> _refresh({bool blocking = false}) async {
    if (_refreshing && !blocking) return;
    if (mounted)
      setState(() {
        _refreshing = true;
        if (blocking) _loading = true;
        _error = null;
      });
    try {
      final value = await widget.details.refresh(
        widget.module,
        widget.result.href,
      );
      if (mounted) {
        _apply(value);
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_details == null) _error = error.toString();
      });
      if (_details != null)
        showFToast(
          context: context,
          title: Text('Could not refresh: $error'),
          alignment: .topRight,
        );
    }
  }

  void _apply(CachedExtensionDetails value) {
    _details = value.details;
    _episodes = value.episodes;
    final seasons = groupSoraEpisodesBySeason(_episodes).keys;
    if (_season == null || !seasons.contains(_season)) {
      _season = seasons.isEmpty ? null : seasons.first;
    }
  }

  Future<void> _openEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    try {
      await openExtensionEpisode(
        context: context,
        module: widget.module,
        result: widget.result,
        episodes: _episodes,
        index: index,
        service: widget.service,
        library: widget.library,
        downloads: widget.downloads,
        details: _details,
      );
    } catch (error) {
      if (mounted)
        showFToast(
          context: context,
          title: Text(error.toString()),
          alignment: .topRight,
        );
    }
  }

  Future<void> _downloadEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    final episode = _episodes[index];
    final id = '${widget.module.id}:${episode.href}';
    if (widget.downloads.contains(id)) {
      showFToast(
        context: context,
        title: const Text('This episode is already in Downloads.'),
        alignment: .topRight,
      );
      return;
    }
    try {
      final streams = await runEpisodeOperation(
        context,
        () => widget.service.streams(widget.module, episode),
      );
      if (streams == null) return;
      if (streams.streams.isEmpty) {
        throw StateError('The extension returned no downloadable streams.');
      }
      final stream = streams.streams.length == 1
          ? streams.streams.first
          : await _pickQuality(streams.streams);
      if (stream == null || !mounted) return;
      unawaited(
        widget.downloads.add(
          DownloadRequest(
            id: id,
            mediaId: libraryMediaFor(widget.module, widget.result).id,
            title: widget.result.title,
            episodeLabel: episode.label,
            imageUrl: widget.result.imageUrl,
            sourceName: widget.module.metadata.sourceName,
            sourceIconUrl: widget.module.metadata.iconUrl,
            sourceType: widget.module.metadata.kind.label,
            qualityLabel: stream.title,
            url: stream.url,
            headers: stream.headers,
            season: episode.season ?? 1,
            episodeNumber: episode.number,
          ),
        ),
      );
      showFToast(
        context: context,
        title: const Text('Download started'),
        alignment: .topRight,
      );
    } catch (error) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text(error.toString()),
          alignment: .topRight,
        );
      }
    }
  }

  Future<SoraStream?> _pickQuality(List<SoraStream> streams) async {
    var selected = 0;
    return showFDialog<SoraStream>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Download quality',
        builder: (_, _) => StatefulBuilder(
          builder: (context, setDialogState) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download quality',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FSelect<int>(
                  items: {
                    for (final stream in streams.indexed)
                      '${stream.$2.title}${streams.where((item) => item.title == stream.$2.title).length > 1 ? ' ${stream.$1 + 1}' : ''}':
                          stream.$1,
                  },
                  control: .lifted(
                    value: selected,
                    onChange: (value) =>
                        setDialogState(() => selected = value ?? 0),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FButton(
                      variant: .outline,
                      mainAxisSize: .min,
                      onPress: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      mainAxisSize: .min,
                      onPress: () =>
                          Navigator.pop(dialogContext, streams[selected]),
                      child: const Text('Download'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupSoraEpisodesBySeason(_episodes, ascending: _ascending);
    final episodeIndices = {
      for (final item in _episodes.indexed) item.$2: item.$1,
    };
    final groups = [
      for (final entry in grouped.entries)
        MediaDetailGroup<SoraEpisode>(
          label: 'Season ${entry.key}',
          value: entry.key.toString(),
          items: [
            for (final episode in entry.value)
              (item: episode, originalIndex: episodeIndices[episode]!),
          ],
        ),
    ];
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MediaDetailHeader(
              title: widget.result.title,
              refreshTooltip: 'Refresh episodes',
              refreshing: _refreshing,
              onRefresh: _refresh,
              bookmarks: widget.library,
              isBookmarked: () {
                final media = libraryMediaFor(widget.module, widget.result);
                return widget.library.contains(media.id);
              },
              onBookmark: () => widget.library.toggle(
                libraryMediaFor(widget.module, widget.result),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : MediaDetailContent<SoraEpisode>(
                      title: widget.result.title,
                      posterUrl: widget.result.imageUrl,
                      posterFallbackIcon: Icons.movie_outlined,
                      metadata: [_details!.airdate, _details!.aliases],
                      description: _details!.description,
                      sectionTitle: 'Episodes',
                      groups: groups,
                      selectedGroup: _season?.toString(),
                      onGroupChanged: (season) =>
                          setState(() => _season = int.tryParse(season ?? '')),
                      ascending: _ascending,
                      onSort: () => setState(() => _ascending = !_ascending),
                      sortAscendingTooltip: 'Sort episodes ascending',
                      sortDescendingTooltip: 'Sort episodes descending',
                      emptyMessage: 'No episodes returned.',
                      itemBuilder: (context, episode, index) => MediaDetailItem(
                        leading: episode.imageUrl.isEmpty
                            ? const Icon(Icons.play_circle_outline)
                            : TerraNetworkImage(
                                url: episode.imageUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                error: const Icon(Icons.play_circle_outline),
                              ),
                        title: Text(episode.label),
                        subtitle: Text('Season ${episode.season ?? 1}'),
                        actions: [
                          ListenableBuilder(
                            listenable: widget.downloads,
                            builder: (context, _) => IconButton(
                              tooltip:
                                  widget.downloads.contains(
                                    '${widget.module.id}:${episode.href}',
                                  )
                                  ? 'In Downloads'
                                  : 'Download episode',
                              onPressed: () => _downloadEpisode(index),
                              icon: Icon(
                                widget.downloads.contains(
                                      '${widget.module.id}:${episode.href}',
                                    )
                                    ? Icons.download_done
                                    : Icons.download_outlined,
                              ),
                            ),
                          ),
                        ],
                        openIcon: Icons.play_arrow,
                        onOpen: () => _openEpisode(index),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
