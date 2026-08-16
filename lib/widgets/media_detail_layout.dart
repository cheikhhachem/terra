import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'terra_header.dart';
import 'terra_network_image.dart';

class MediaDetailGroup<T> {
  const MediaDetailGroup({
    required this.label,
    required this.value,
    required this.items,
  });

  final String label;
  final String value;
  final List<({T item, int originalIndex})> items;
}

class MediaDetailHeader extends StatelessWidget {
  const MediaDetailHeader({
    super.key,
    required this.title,
    required this.refreshTooltip,
    required this.refreshing,
    required this.onRefresh,
    required this.bookmarks,
    required this.isBookmarked,
    required this.onBookmark,
  });

  final String title;
  final String refreshTooltip;
  final bool refreshing;
  final VoidCallback onRefresh;
  final Listenable bookmarks;
  final bool Function() isBookmarked;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) => TerraHeader(
    title: Text(title),
    actions: [
      if (refreshing)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      FHeaderAction(
        semanticsTooltip: refreshTooltip,
        onPress: refreshing ? null : onRefresh,
        icon: const Icon(Icons.refresh),
      ),
      ListenableBuilder(
        listenable: bookmarks,
        builder: (context, _) {
          final saved = isBookmarked();
          return FHeaderAction(
            semanticsTooltip: saved ? 'Remove from library' : 'Add to library',
            onPress: onBookmark,
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          );
        },
      ),
    ],
  );
}

class MediaDetailContent<T> extends StatelessWidget {
  const MediaDetailContent({
    super.key,
    required this.title,
    required this.posterUrl,
    required this.posterFallbackIcon,
    required this.metadata,
    required this.description,
    required this.sectionTitle,
    required this.groups,
    required this.selectedGroup,
    required this.onGroupChanged,
    required this.ascending,
    required this.onSort,
    required this.emptyMessage,
    required this.itemBuilder,
    required this.sortAscendingTooltip,
    required this.sortDescendingTooltip,
  });

  final String title;
  final String posterUrl;
  final IconData posterFallbackIcon;
  final List<String> metadata;
  final String description;
  final String sectionTitle;
  final List<MediaDetailGroup<T>> groups;
  final String? selectedGroup;
  final ValueChanged<String?> onGroupChanged;
  final bool ascending;
  final VoidCallback onSort;
  final String emptyMessage;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final String sortAscendingTooltip;
  final String sortDescendingTooltip;

  @override
  Widget build(BuildContext context) {
    final group =
        groups.where((group) => group.value == selectedGroup).firstOrNull ??
        groups.firstOrNull;
    final items = group?.items ?? const [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 180,
                child: posterUrl.isEmpty
                    ? ColoredBox(
                        color: Colors.black12,
                        child: Icon(posterFallbackIcon),
                      )
                    : TerraNetworkImage(
                        url: posterUrl,
                        fit: BoxFit.cover,
                        error: ColoredBox(
                          color: Colors.black12,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  for (final value in metadata.where(
                    (value) => value.isNotEmpty,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(value),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: _ExpandableDescription(description),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                sectionTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (groups.length > 1)
              SizedBox(
                width: 140,
                child: FSelect<String>(
                  items: {for (final group in groups) group.label: group.value},
                  control: .lifted(
                    value: group?.value,
                    onChange: onGroupChanged,
                  ),
                  hint: 'Group',
                ),
              ),
            IconButton(
              tooltip: ascending ? sortDescendingTooltip : sortAscendingTooltip,
              onPressed: onSort,
              icon: Icon(ascending ? Icons.arrow_downward : Icons.arrow_upward),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(emptyMessage)),
          )
        else
          ...items.map(
            (entry) => itemBuilder(context, entry.item, entry.originalIndex),
          ),
      ],
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription(this.text);

  final String text;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style;
      final text = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 3,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (text.didExceedMaxLines)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Less' : 'More'),
            ),
        ],
      );
    },
  );
}

class MediaDetailItem extends StatelessWidget {
  const MediaDetailItem({
    super.key,
    required this.leading,
    required this.title,
    required this.onOpen,
    this.subtitle,
    this.actions = const [],
    this.openIcon = Icons.open_in_new,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final VoidCallback onOpen;
  final IconData openIcon;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [...actions, Icon(openIcon)],
      ),
      onTap: onOpen,
    ),
  );
}
