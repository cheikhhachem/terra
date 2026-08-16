// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../downloads/download_repository.dart';
import '../library/library_repository.dart';
import '../library/media_poster_card.dart';
import '../reading/read_detail_page.dart';
import '../reading/read_download_repository.dart';
import '../reading/reading_models.dart';
import '../../widgets/terra_header.dart';
import '../../widgets/source_icon.dart';
import '../../widgets/horizontal_edge_fade.dart';
import 'extension_detail_page.dart';
import 'extension_detail_repository.dart';
import 'extension_navigation.dart';
import 'extension_manager.dart';
import 'models.dart';
import 'sora_extension_service.dart';

class ExtensionSearchPage extends StatefulWidget {
  const ExtensionSearchPage({
    super.key,
    required this.manager,
    required this.service,
    required this.details,
    required this.library,
    required this.downloads,
    required this.readDownloads,
  });
  final ExtensionManager manager;
  final ExtensionService service;
  final ExtensionDetailRepository details;
  final LibraryRepository library;
  final DownloadRepository downloads;
  final ReadDownloadRepository readDownloads;

  @override
  State<ExtensionSearchPage> createState() => _ExtensionSearchPageState();
}

class _ExtensionSearchPageState extends State<ExtensionSearchPage> {
  static const _historyKey = 'terra.search.history.v1';
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history =
        await SharedPreferencesAsync().getStringList(_historyKey) ?? const [];
    if (mounted) setState(() => _history = history);
  }

  Future<void> _remember(String query) async {
    final normalized = query.toLowerCase();
    setState(() {
      _history = [
        query,
        ..._history.where((item) => item.toLowerCase() != normalized),
      ].take(20).toList();
    });
    await SharedPreferencesAsync().setStringList(_historyKey, _history);
  }

  Future<void> _removeHistory(String query) async {
    setState(() => _history.remove(query));
    await SharedPreferencesAsync().setStringList(_historyKey, _history);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: FTabs(
      expands: true,
      children: [
        FTabEntry(
          label: const Text('Watch'),
          child: _SearchTab<SoraSearchResult>(
            sourcesListenable: widget.manager,
            activeSources: () => widget.manager.activeWatchInstalled,
            search: widget.service.search,
            sourceLabel: (module) =>
                '${module.metadata.sourceName} · ${module.metadata.kind.label}',
            resultBuilder: (context, module, result) => _ResultCard(
              module: module,
              result: result,
              library: widget.library,
              onTap: () => _openDetail(
                context,
                module,
                result,
                widget.service,
                widget.details,
                widget.library,
                widget.downloads,
              ),
            ),
            history: _history,
            remember: _remember,
            removeHistory: _removeHistory,
            hintText: 'Title',
            emptyTitle: 'No active sources',
            emptyDetail: 'Install a source and turn on its active switch.',
            idleIcon: Icons.travel_explore,
            idleTitle: 'Find something to watch',
            idleDetail: 'Submit a title to search every active extension.',
          ),
        ),
        FTabEntry(
          label: const Text('Read'),
          child: _SearchTab<ReadSearchResult>(
            sourcesListenable: widget.manager,
            activeSources: () => widget.manager.activeReadInstalled,
            search: widget.service.searchRead,
            sourceLabel: (module) =>
                '${module.metadata.sourceName} · ${widget.service.readKind(module).name}',
            resultBuilder: (context, module, result) => MediaPosterCard(
              title: result.title,
              subtitle: module.metadata.sourceName,
              imageUrl: result.imageUrl,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadDetailPage(
                    module: module,
                    result: result,
                    service: widget.service,
                    library: widget.library,
                    downloads: widget.readDownloads,
                  ),
                ),
              ),
            ),
            history: _history,
            remember: _remember,
            removeHistory: _removeHistory,
            hintText: 'Manga or novel title',
            emptyTitle: 'No active reading sources',
            emptyDetail:
                'Install a manga or novel source and turn on its active switch.',
            idleIcon: Icons.auto_stories_outlined,
            idleTitle: 'Find something to read',
            idleDetail: 'Search every active manga and novel source.',
          ),
        ),
      ],
    ),
  );
}

class _SearchTab<T> extends StatefulWidget {
  const _SearchTab({
    required this.sourcesListenable,
    required this.activeSources,
    required this.search,
    required this.sourceLabel,
    required this.resultBuilder,
    required this.history,
    required this.remember,
    required this.removeHistory,
    required this.hintText,
    required this.emptyTitle,
    required this.emptyDetail,
    required this.idleIcon,
    required this.idleTitle,
    required this.idleDetail,
  });
  final Listenable sourcesListenable;
  final List<InstalledSoraModule> Function() activeSources;
  final Future<List<T>> Function(InstalledSoraModule, String) search;
  final String Function(InstalledSoraModule) sourceLabel;
  final Widget Function(BuildContext, InstalledSoraModule, T) resultBuilder;
  final List<String> history;
  final Future<void> Function(String) remember;
  final Future<void> Function(String) removeHistory;
  final String hintText;
  final String emptyTitle;
  final String emptyDetail;
  final IconData idleIcon;
  final String idleTitle;
  final String idleDetail;

  @override
  State<_SearchTab<T>> createState() => _SearchTabState<T>();
}

class _SearchTabState<T> extends State<_SearchTab<T>> {
  final _query = TextEditingController();
  final Map<String, _SourceSearch<T>> _searches = {};
  int _generation = 0;
  int _resultOrder = 0;
  bool _submitted = false;

  List<String> get _suggestions {
    final query = _query.text.trim().toLowerCase();
    return widget.history
        .where((item) => query.isEmpty || item.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final modules = widget.activeSources();
    if (query.isEmpty || modules.isEmpty) return;
    unawaited(widget.remember(query));
    final generation = ++_generation;
    setState(() {
      _submitted = true;
      _resultOrder = 0;
      _searches
        ..clear()
        ..addEntries(
          modules.map(
            (module) => MapEntry(module.id, _SourceSearch<T>(module: module)),
          ),
        );
    });
    await Future.wait(
      modules.map((module) => _searchSource(module, query, generation)),
    );
  }

  Future<void> _searchSource(
    InstalledSoraModule module,
    String query,
    int generation,
  ) async {
    try {
      final results = await widget.search(module, query);
      if (mounted && generation == _generation)
        setState(() {
          _searches[module.id] = _SourceSearch<T>(
            module: module,
            results: results,
            loading: false,
            resultOrder: results.isEmpty ? null : _resultOrder++,
          );
        });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(
          () => _searches[module.id] = _SourceSearch<T>(
            module: module,
            loading: false,
            error: error.toString(),
          ),
        );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.sourcesListenable,
    builder: (context, _) {
      final active = widget.activeSources();
      final compact = MediaQuery.sizeOf(context).width < 600;
      return ListView(
        padding: EdgeInsets.all(compact ? 12 : 16),
        children: [
          TextField(
            controller: _query,
            enabled: active.isNotEmpty,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() => _submitted = false),
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: active.isEmpty ? null : _search,
                icon: const Icon(Icons.arrow_forward),
              ),
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
            ),
          ),
          if (!_submitted && _suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._suggestions.map(
              (item) => Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(item),
                  trailing: IconButton(
                    tooltip: 'Remove from search history',
                    onPressed: () => widget.removeHistory(item),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                  onTap: () {
                    _query.text = item;
                    _query.selection = TextSelection.collapsed(
                      offset: item.length,
                    );
                    _search();
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (active.isEmpty)
            _Status(
              icon: Icons.extension_off_outlined,
              title: widget.emptyTitle,
              detail: widget.emptyDetail,
            )
          else if (!_submitted)
            _Status(
              icon: widget.idleIcon,
              title: widget.idleTitle,
              detail: widget.idleDetail,
            )
          else
            ...(_searches.values
                    .where(
                      (search) =>
                          active.any((module) => module.id == search.module.id),
                    )
                    .toList()
                  ..sort(_compareSearches<T>))
                .map(
                  (search) => _SourceResults<T>(
                    search: search,
                    compact: compact,
                    sourceLabel: widget.sourceLabel,
                    resultBuilder: widget.resultBuilder,
                  ),
                ),
        ],
      );
    },
  );
}

class _SourceSearch<T> {
  const _SourceSearch({
    required this.module,
    this.results = const [],
    this.loading = true,
    this.error,
    this.resultOrder,
  });
  final InstalledSoraModule module;
  final List<T> results;
  final bool loading;
  final String? error;
  final int? resultOrder;
}

int _compareSearches<T>(_SourceSearch<T> a, _SourceSearch<T> b) {
  final aHasResults = a.results.isNotEmpty;
  final bHasResults = b.results.isNotEmpty;
  if (aHasResults != bHasResults) return aHasResults ? -1 : 1;
  if (aHasResults) return a.resultOrder!.compareTo(b.resultOrder!);
  if (a.loading != b.loading) return a.loading ? -1 : 1;
  return 0;
}

class _SourceResults<T> extends StatelessWidget {
  const _SourceResults({
    required this.search,
    required this.compact,
    required this.sourceLabel,
    required this.resultBuilder,
  });
  final _SourceSearch<T> search;
  final bool compact;
  final String Function(InstalledSoraModule) sourceLabel;
  final Widget Function(BuildContext, InstalledSoraModule, T) resultBuilder;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: search.results.isEmpty ? 8 : 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SourceIcon(url: search.module.metadata.iconUrl, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sourceLabel(search.module),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (search.loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (search.error != null)
              Tooltip(
                message: search.error!,
                child: const Icon(Icons.error_outline, size: 20),
              ),
            IconButton(
              tooltip: 'Show all results',
              onPressed: search.results.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ExpandedSourceResults<T>(
                          search: search,
                          resultBuilder: resultBuilder,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
        if (search.results.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? 196 : 230,
            child: HorizontalEdgeFade(
              builder: (controller) => ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: search.results.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: compact ? 128 : 150,
                  child: resultBuilder(
                    context,
                    search.module,
                    search.results[index],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ExpandedSourceResults<T> extends StatelessWidget {
  const _ExpandedSourceResults({
    required this.search,
    required this.resultBuilder,
  });
  final _SourceSearch<T> search;
  final Widget Function(BuildContext, InstalledSoraModule, T) resultBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          TerraHeader(
            title: Row(
              children: [
                SourceIcon(url: search.module.metadata.iconUrl, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(search.module.metadata.sourceName)),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 250,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: search.results.length,
                  itemBuilder: (context, index) => resultBuilder(
                    context,
                    search.module,
                    search.results[index],
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

void _openDetail(
  BuildContext context,
  InstalledSoraModule module,
  SoraSearchResult result,
  ExtensionService service,
  ExtensionDetailRepository details,
  LibraryRepository library,
  DownloadRepository downloads,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ExtensionDetailPage(
      module: module,
      result: result,
      service: service,
      details: details,
      library: library,
      downloads: downloads,
    ),
  ),
);

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.module,
    required this.result,
    required this.library,
    required this.onTap,
  });
  final InstalledSoraModule module;
  final SoraSearchResult result;
  final LibraryRepository library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final media = libraryMediaFor(module, result);
      final saved = library.contains(media.id);
      return MediaPosterCard(
        title: result.title,
        imageUrl: result.imageUrl,
        onTap: onTap,
        action: IconButton.filledTonal(
          tooltip: saved ? 'Remove from library' : 'Add to library',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          onPressed: () => library.toggle(media),
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
        ),
      );
    },
  );
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        Icon(icon, size: 48),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}
