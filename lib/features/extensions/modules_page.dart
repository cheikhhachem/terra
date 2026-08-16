import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../widgets/terra_header.dart';
import '../../widgets/source_icon.dart';
import '../../widgets/marquee_text.dart';
import 'extension_manager.dart';
import 'extension_facets.dart';
import 'models.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key, required this.manager});
  final ExtensionManager manager;

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  String? _busy;
  String? _language;
  String? _type;
  ExtensionKind? _kind;
  ExtensionMediaMode? _mode;

  Future<void> _run(String key, Future<void> Function() operation) async {
    setState(() {
      _busy = key;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text(
            error.toString().replaceFirst(
              RegExp(r'^(Bad state|FormatException):\s*'),
              '',
            ),
          ),
          alignment: .topRight,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _showAddDialog() async {
    var input = '';
    var error = '';
    final url = await showFDialog<String>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Add source',
        builder: (_, _) => StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final uri = Uri.tryParse(input.trim());
              if (uri == null || !uri.hasScheme) {
                setDialogState(() => error = 'Enter a valid metadata URL.');
                return;
              }
              Navigator.pop(dialogContext, uri.toString());
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add source',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    control: FTextFieldControl.managed(
                      onChange: (value) => input = value.text,
                    ),
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    label: const Text('Metadata URL'),
                    hint: 'Module JSON or Mangayomi index JSON',
                    error: error.isEmpty ? null : Text(error),
                    onSubmit: (_) => submit(),
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
                        onPress: submit,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (url != null) await _run('add', () => widget.manager.addSource(url));
  }

  Future<void> _showManageSources() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManageSourcesPage(
          manager: widget.manager,
          onAdd: _showAddDialog,
          onEdit: _editSources,
          onRemove: (sources) async {
            final repository = sources.length > 1;
            if (await _confirmRemoval(
              repository
                  ? 'Remove this repository and all its plugins?'
                  : 'Remove this source?',
            )) {
              await _run(
                'remove-${sources.first.id}',
                () => widget.manager.removeSources(sources),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _editSources(List<KnownSoraSource> sources) async {
    var input = sources.first.metadataUrl;
    final url = await showFDialog<String>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Edit source link',
        builder: (_, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit source link',
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FTextField(
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(text: input),
                  onChange: (value) => input = value.text,
                ),
                label: const Text('Metadata URL'),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmit: (_) => Navigator.pop(dialogContext, input.trim()),
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
                    onPress: () => Navigator.pop(dialogContext, input.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (url == null || url == sources.first.metadataUrl) return;
    await _run(
      'edit-${sources.first.id}',
      () => widget.manager.refreshSources(sources, url),
    );
  }

  Future<bool> _confirmRemoval(String title) async =>
      await showFDialog<bool>(
        context: context,
        builder: (dialogContext, _, animation) => FDialog(
          animation: animation,
          semanticsLabel: title,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Installed copies will also be removed.'),
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
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;

  Future<void> _showFilters() async {
    final languages =
        widget.manager.knownSources
            .expand((source) => extensionLanguages(source.metadata.language))
            .where((value) => value != allLanguages)
            .toSet()
            .toList()
          ..sort();
    final types =
        widget.manager.knownSources
            .expand((source) => extensionMediaTypes(source.metadata.type))
            .toSet()
            .toList()
          ..sort();
    var language = _language;
    var type = _type;
    var kind = _kind;
    var mode = _mode;
    await showFDialog<void>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Filter sources',
        builder: (_, _) => StatefulBuilder(
          builder: (context, setDialogState) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter sources',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FSelect<String>(
                  label: const Text('Language'),
                  items: {
                    'All': '',
                    for (final value in languages) value: value,
                  },
                  control: .lifted(
                    value: language ?? '',
                    onChange: (value) => setDialogState(
                      () => language = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FSelect<ExtensionKind?>(
                  label: const Text('Extension type'),
                  items: {
                    'All': null,
                    for (final value in ExtensionKind.values)
                      value.label: value,
                  },
                  control: .lifted(
                    value: kind,
                    onChange: (value) => setDialogState(() => kind = value),
                  ),
                ),
                const SizedBox(height: 12),
                FSelect<ExtensionMediaMode?>(
                  label: const Text('Mode'),
                  items: {
                    'All': null,
                    for (final value in ExtensionMediaMode.values)
                      value.label: value,
                  },
                  control: .lifted(
                    value: mode,
                    onChange: (value) => setDialogState(() => mode = value),
                  ),
                ),
                const SizedBox(height: 12),
                FSelect<String>(
                  label: const Text('Type'),
                  items: {'All': '', for (final value in types) value: value},
                  control: .lifted(
                    value: type ?? '',
                    onChange: (value) => setDialogState(
                      () =>
                          type = value == null || value.isEmpty ? null : value,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FButton(
                      variant: .outline,
                      mainAxisSize: .min,
                      onPress: () {
                        setState(() {
                          _language = null;
                          _type = null;
                          _kind = null;
                          _mode = null;
                        });
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      mainAxisSize: .min,
                      onPress: () {
                        setState(() {
                          _language = language;
                          _type = type;
                          _kind = kind;
                          _mode = mode;
                        });
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('Apply'),
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

  bool _matches(KnownSoraSource source) {
    final languages = extensionLanguages(source.metadata.language);
    final types = extensionMediaTypes(source.metadata.type);
    final modes = extensionMediaModes(
      source.metadata.type,
      novel: source.metadata.novel,
    );
    return (_language == null ||
            languages.contains(allLanguages) ||
            languages.contains(_language)) &&
        (_type == null || types.contains(_type)) &&
        (_mode == null || modes.contains(_mode)) &&
        (_kind == null || source.metadata.kind == _kind);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          TerraHeader(
            title: const Text('Modules'),
            actions: [
              FHeaderAction(
                semanticsTooltip: 'Refresh all sources',
                onPress: _busy == null && widget.manager.knownSources.isNotEmpty
                    ? () =>
                          _run('refresh-all', widget.manager.refreshAllSources)
                    : null,
                icon: const Icon(Icons.refresh),
              ),
              FHeaderAction(
                semanticsTooltip: 'Filter sources',
                onPress: _showFilters,
                icon: Icon(
                  _language == null &&
                          _type == null &&
                          _kind == null &&
                          _mode == null
                      ? Icons.filter_list
                      : Icons.filter_list_alt,
                ),
              ),
              FHeaderAction(
                semanticsTooltip: 'Add source',
                onPress: _busy == null ? _showAddDialog : null,
                icon: const Icon(Icons.add),
              ),
              FHeaderAction(
                semanticsTooltip: 'Manage source links',
                onPress: _busy == null && widget.manager.knownSources.isNotEmpty
                    ? _showManageSources
                    : null,
                icon: const Icon(Icons.link_outlined),
              ),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.manager,
              builder: (context, _) {
                if (!widget.manager.initialized) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (widget.manager.initializationError != null) {
                  return Center(
                    child: Text(widget.manager.initializationError!),
                  );
                }
                final sources = widget.manager.knownSources
                    .where(_matches)
                    .toList();
                final installed = sources
                    .where(
                      (source) =>
                          widget.manager.installationFor(source) != null,
                    )
                    .toList();
                final notInstalled = sources
                    .where(
                      (source) =>
                          widget.manager.installationFor(source) == null,
                    )
                    .toList();
                return Column(
                  children: [
                    Expanded(
                      child: FTabs(
                        expands: true,
                        children: [
                          FTabEntry(
                            label: const Text('Sources'),
                            child: _SourcesList(
                              installed: installed,
                              notInstalled: notInstalled,
                              tile: _sourceTile,
                            ),
                          ),
                          FTabEntry(
                            label: const Text('Installed'),
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: installed.isEmpty
                                  ? const [
                                      Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Center(
                                          child: Text('No sources installed.'),
                                        ),
                                      ),
                                    ]
                                  : installed.map(_installedTile).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sourceTile(KnownSoraSource source) {
    final module = widget.manager.installationFor(source);
    return Card(
      child: ListTile(
        title: MarqueeText(
          source.metadata.sourceName,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: MarqueeText(
          _subtitle(source.metadata),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        leading: SourceIcon(url: source.metadata.iconUrl),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (source.metadataUrl.isNotEmpty)
              IconButton(
                tooltip: 'Refresh',
                onPressed: _busy == null
                    ? () => _run(
                        'refresh-${source.id}',
                        () => widget.manager.refresh(source),
                      )
                    : null,
                icon: const Icon(Icons.refresh),
              ),
            IconButton(
              tooltip: module == null ? 'Install' : 'Uninstall',
              onPressed: _busy == null
                  ? () => _run(
                      '${module == null ? 'install' : 'uninstall'}-${source.id}',
                      () => module == null
                          ? widget.manager.install(source)
                          : widget.manager.uninstall(source),
                    )
                  : null,
              icon: Icon(
                module == null
                    ? Icons.download_outlined
                    : Icons.remove_circle_outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _installedTile(KnownSoraSource source) {
    final module = widget.manager.installationFor(source)!;
    return Card(
      child: ListTile(
        title: MarqueeText(
          source.metadata.sourceName,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: MarqueeText(
          _subtitle(source.metadata),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        leading: SourceIcon(url: source.metadata.iconUrl),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: module.active,
              onChanged: _busy == null
                  ? (value) => _run(
                      'active-${source.id}',
                      () => widget.manager.setActive(module, value),
                    )
                  : null,
            ),
            IconButton(
              tooltip: 'Uninstall',
              onPressed: _busy == null
                  ? () => _run(
                      'uninstall-${source.id}',
                      () => widget.manager.uninstall(source),
                    )
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(SoraMetadata metadata) => [
    metadata.version.isEmpty ? 'Unknown version' : 'v${metadata.version}',
    if (extensionLanguages(metadata.language).isNotEmpty)
      extensionLanguages(metadata.language).join(', '),
    if (extensionMediaTypes(metadata.type).isNotEmpty)
      extensionMediaTypes(metadata.type).join('/'),
    metadata.kind.label,
  ].join(' · ');
}

class _ManageSourcesPage extends StatelessWidget {
  const _ManageSourcesPage({
    required this.manager,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final ExtensionManager manager;
  final Future<void> Function() onAdd;
  final Future<void> Function(List<KnownSoraSource> sources) onEdit;
  final Future<void> Function(List<KnownSoraSource> sources) onRemove;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          TerraHeader(
            title: const Text('Manage source links'),
            nested: true,
            actions: [
              FHeaderAction(
                semanticsTooltip: 'Add source',
                onPress: onAdd,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: manager,
              builder: (context, _) {
                final groups = _sourceGroups(manager.knownSources);
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ManagedSourceCard(
                    group: groups[index],
                    onEdit: onEdit,
                    onRemove: onRemove,
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

class _ManagedSourceCard extends StatefulWidget {
  const _ManagedSourceCard({
    required this.group,
    required this.onEdit,
    required this.onRemove,
  });

  final _SourceGroup group;
  final Future<void> Function(List<KnownSoraSource> sources) onEdit;
  final Future<void> Function(List<KnownSoraSource> sources) onRemove;

  @override
  State<_ManagedSourceCard> createState() => _ManagedSourceCardState();
}

class _ManagedSourceCardState extends State<_ManagedSourceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          _parent(context),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: widget.group.sources
                    .map((source) => _plugin(context, source))
                    .toList(),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _parent(BuildContext context) {
    final source = widget.group.sources.first;
    final types = extensionMediaTypes(source.metadata.type);
    return Row(
      children: [
        SourceIcon(url: source.metadata.iconUrl, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarqueeText(
                widget.group.repository
                    ? 'Mangayomi repository'
                    : source.metadata.sourceName,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              MarqueeText(
                widget.group.repository
                    ? '${widget.group.sources.length} plugins · ${Uri.parse(widget.group.metadataUrl).host}'
                    : '${source.metadata.kind.label} · ${types.isEmpty ? 'Source' : types.join('/')}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        if (widget.group.repository)
          IconButton(
            tooltip: _expanded ? 'Collapse plugins' : 'Expand plugins',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: AnimatedRotation(
              turns: _expanded ? .5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
          ),
        IconButton(
          tooltip: 'Copy link',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: widget.group.metadataUrl),
            );
            if (context.mounted) {
              showFToast(
                context: context,
                title: const Text('Link copied'),
                alignment: .topRight,
              );
            }
          },
          icon: const Icon(Icons.copy_outlined, size: 20),
        ),
        IconButton(
          tooltip: 'Edit link',
          visualDensity: VisualDensity.compact,
          onPressed: () => widget.onEdit(widget.group.sources),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          tooltip: 'Remove source',
          visualDensity: VisualDensity.compact,
          onPressed: () => widget.onRemove(widget.group.sources),
          icon: const Icon(Icons.delete_outline, size: 20),
        ),
      ],
    );
  }

  Widget _plugin(BuildContext context, KnownSoraSource source) {
    final details = <String>[
      if (source.metadata.version.isNotEmpty) 'v${source.metadata.version}',
      ...extensionLanguages(source.metadata.language),
      ...extensionMediaTypes(source.metadata.type),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SourceIcon(url: source.metadata.iconUrl, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarqueeText(
                  source.metadata.sourceName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                MarqueeText(
                  details.join(' · '),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceGroup {
  const _SourceGroup(this.metadataUrl, this.sources);
  final String metadataUrl;
  final List<KnownSoraSource> sources;

  bool get repository =>
      sources.first.metadata.kind == ExtensionKind.mangayomi &&
      sources.first.id.contains('#');
}

List<_SourceGroup> _sourceGroups(List<KnownSoraSource> sources) {
  final grouped = <String, List<KnownSoraSource>>{};
  for (final source in sources) {
    grouped.putIfAbsent(source.metadataUrl, () => []).add(source);
  }
  return [
    for (final entry in grouped.entries) _SourceGroup(entry.key, entry.value),
  ];
}

class _SourcesList extends StatelessWidget {
  const _SourcesList({
    required this.installed,
    required this.notInstalled,
    required this.tile,
  });
  final List<KnownSoraSource> installed;
  final List<KnownSoraSource> notInstalled;
  final Widget Function(KnownSoraSource) tile;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Installed', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (installed.isEmpty)
        const Text('No installed sources match.')
      else
        ...installed.map(tile),
      const SizedBox(height: 24),
      Text('Not installed', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (notInstalled.isEmpty)
        const Text('No uninstalled sources match.')
      else
        ...notInstalled.map(tile),
    ],
  );
}
