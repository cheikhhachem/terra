// Derived from Mangayomi, licensed under the Apache License 2.0.
// https://github.com/kodjodevf/mangayomi

import 'dart:async';

import 'package:flutter/material.dart';

import 'mangayomi_reader_settings.dart';

Future<void> showMangayomiMangaSettings({
  required BuildContext context,
  required MangayomiReaderSettings settings,
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _MangaSettingsSheet(settings: settings, onChanged: onChanged),
);

Future<void> showMangayomiNovelSettings({
  required BuildContext context,
  required MangayomiReaderSettings settings,
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _NovelSettingsSheet(settings: settings, onChanged: onChanged),
);

abstract class _SettingsState<T extends StatefulWidget> extends State<T> {
  MangayomiReaderSettings get settings;
  VoidCallback get onSettingsChanged;

  void change(VoidCallback update) {
    setState(update);
    unawaited(settings.save());
    onSettingsChanged();
  }
}

class _MangaSettingsSheet extends StatefulWidget {
  const _MangaSettingsSheet({required this.settings, required this.onChanged});

  final MangayomiReaderSettings settings;
  final VoidCallback onChanged;

  @override
  State<_MangaSettingsSheet> createState() => _MangaSettingsSheetState();
}

class _MangaSettingsSheetState extends _SettingsState<_MangaSettingsSheet> {
  @override
  MangayomiReaderSettings get settings => widget.settings;

  @override
  VoidCallback get onSettingsChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            const _SheetHandle(),
            const TabBar(
              tabs: [
                Tab(text: 'Reading mode'),
                Tab(text: 'General'),
                Tab(text: 'Color'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _scroll(_readingModeTab()),
                  _scroll(_generalTab()),
                  _scroll(_colorTab()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: child,
  );

  Widget _readingModeTab() {
    final continuous = settings.mode.isContinuous;
    return Column(
      children: [
        _DropdownSetting<ReaderMode>(
          title: 'Reading mode',
          value: settings.mode,
          values: ReaderMode.values,
          label: (value) => value.label,
          onChanged: (value) => change(() => settings.mode = value),
        ),
        _switch('Crop borders', settings.cropBorders, (value) {
          settings.cropBorders = value;
        }),
        if (continuous) ...[
          _switch('Disable zoom out', settings.disableZoomOut, (value) {
            settings.disableZoomOut = value;
          }),
        ],
        _DropdownSetting<PageMode>(
          title: 'Page mode',
          value: settings.pageMode,
          values: PageMode.values,
          label: (value) => switch (value) {
            PageMode.onePage => 'Single page',
            PageMode.doublePage => 'Double page',
          },
          onChanged: (value) => change(() => settings.pageMode = value),
        ),
        _switch('Use page tap zones', settings.usePageTapZones, (value) {
          settings.usePageTapZones = value;
        }),
        _switch('Keep screen on', settings.keepScreenOn, (value) {
          settings.keepScreenOn = value;
        }),
        if (continuous) ...[
          _switch('Show page gaps', settings.showPageGaps, (value) {
            settings.showPageGaps = value;
          }),
          _slider(
            'Side padding',
            settings.sidePadding.toDouble(),
            0,
            50,
            '${settings.sidePadding}%',
            (value) => settings.sidePadding = value.round(),
            divisions: 50,
          ),
          _switch(
            'Auto-scroll',
            settings.autoScroll,
            (value) {
              settings.autoScroll = value;
            },
            secondary: const Icon(Icons.timer_outlined),
          ),
          if (settings.autoScroll)
            _slider(
              'Auto-scroll speed',
              settings.autoScrollSpeed,
              2,
              30,
              settings.autoScrollSpeed.toStringAsFixed(0),
              (value) => settings.autoScrollSpeed = value,
              divisions: 28,
            ),
        ],
      ],
    );
  }

  Widget _generalTab() => Column(
    children: [
      _DropdownSetting<ReaderBackground>(
        title: 'Background',
        value: settings.background,
        values: ReaderBackground.values,
        label: (value) => switch (value) {
          ReaderBackground.black => 'Black',
          ReaderBackground.grey => 'Grey',
          ReaderBackground.white => 'White',
          ReaderBackground.automatic => 'Automatic',
        },
        onChanged: (value) => change(() => settings.background = value),
      ),
      _DropdownSetting<ReaderScaleType>(
        title: 'Scale type',
        value: settings.scaleType,
        values: ReaderScaleType.values,
        label: (value) => value.label,
        onChanged: (value) => change(() => settings.scaleType = value),
      ),
      _DropdownSetting<int>(
        title: 'Navigation layout',
        value: settings.navigationLayout,
        values: const [0, 1, 2, 3, 4, 5],
        label: (value) => const [
          'Default',
          'L-shaped',
          'Kindle',
          'Edge',
          'Right and left',
          'Disabled',
        ][value],
        onChanged: (value) => change(() => settings.navigationLayout = value),
      ),
      _DropdownSetting<int>(
        title: 'Tapping inversion',
        value: settings.tappingInversion,
        values: const [0, 1, 2, 3],
        label: (value) =>
            const ['None', 'Horizontal', 'Vertical', 'Both'][value],
        onChanged: (value) => change(() => settings.tappingInversion = value),
      ),
      _switch('Show page numbers', settings.showPageNumbers, (value) {
        settings.showPageNumbers = value;
      }),
      _switch('Animate page transitions', settings.animatePageTransitions, (
        value,
      ) {
        settings.animatePageTransitions = value;
      }),
    ],
  );

  Widget _colorTab() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Color enhancements'),
      _switch('Invert colors', settings.invertColors, (value) {
        settings.invertColors = value;
      }),
      _switch('Grayscale', settings.grayscale, (value) {
        settings.grayscale = value;
      }),
      _enhancementSlider(
        'Brightness',
        settings.brightness,
        -1,
        1,
        0,
        (value) => settings.brightness = value,
      ),
      _enhancementSlider(
        'Contrast',
        settings.contrast,
        0,
        2,
        1,
        (value) => settings.contrast = value,
      ),
      _enhancementSlider(
        'Saturation',
        settings.saturation,
        0,
        2,
        1,
        (value) => settings.saturation = value,
      ),
    ],
  );

  Widget _switch(
    String title,
    bool value,
    ValueChanged<bool> update, {
    String? subtitle,
    Widget? secondary,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    secondary: secondary,
    value: value,
    onChanged: (value) => change(() => update(value)),
  );

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> update, {
    int? divisions,
  }) => ListTile(
    title: Text('$title: $display'),
    subtitle: Slider(
      min: min,
      max: max,
      divisions: divisions,
      value: value.clamp(min, max),
      label: display,
      onChanged: (value) => change(() => update(value)),
    ),
  );

  Widget _enhancementSlider(
    String title,
    double value,
    double min,
    double max,
    double defaultValue,
    ValueChanged<double> update,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(title)),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: (value) => change(() => update(value)),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.center),
        ),
        SizedBox(
          width: 40,
          child: (value - defaultValue).abs() < .01
              ? null
              : IconButton(
                  tooltip: 'Reset',
                  icon: const Icon(Icons.replay, size: 18),
                  onPressed: () => change(() => update(defaultValue)),
                ),
        ),
      ],
    ),
  );
}

class _NovelSettingsSheet extends StatefulWidget {
  const _NovelSettingsSheet({required this.settings, required this.onChanged});

  final MangayomiReaderSettings settings;
  final VoidCallback onChanged;

  @override
  State<_NovelSettingsSheet> createState() => _NovelSettingsSheetState();
}

class _NovelSettingsSheetState extends _SettingsState<_NovelSettingsSheet> {
  static const _presets = [
    ('Dark', Color(0xff292832), Color(0xffcccccc)),
    ('Light', Colors.white, Colors.black),
    ('Black', Colors.black, Colors.white),
    ('Sepia', Color(0xfff5e6d3), Color(0xff5f4b32)),
  ];

  @override
  MangayomiReaderSettings get settings => widget.settings;

  @override
  VoidCallback get onSettingsChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            const _SheetHandle(),
            const TabBar(
              tabs: [
                Tab(text: 'Reader'),
                Tab(text: 'General'),
                Tab(text: 'TTS'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _readerTab(),
                  ),
                  SingleChildScrollView(child: _generalTab()),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _ttsTab(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readerTab() => Column(
    children: [
      _SettingSection(
        title: 'Theme',
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  _ThemeButton(
                    label: preset.$1,
                    background: preset.$2,
                    foreground: preset.$3,
                    selected:
                        settings.novelBackground.toARGB32() ==
                        preset.$2.toARGB32(),
                    onTap: () => change(() {
                      settings.novelBackground = preset.$2;
                      settings.novelTextColor = preset.$3;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ColorPicker(
                    label: 'Background',
                    color: settings.novelBackground,
                    onChanged: (color) =>
                        change(() => settings.novelBackground = color),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ColorPicker(
                    label: 'Text',
                    color: settings.novelTextColor,
                    onChanged: (color) =>
                        change(() => settings.novelTextColor = color),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingSection(
        title: 'Text alignment',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final option in const [
              (NovelTextAlign.left, Icons.format_align_left),
              (NovelTextAlign.center, Icons.format_align_center),
              (NovelTextAlign.right, Icons.format_align_right),
              (NovelTextAlign.justify, Icons.format_align_justify),
            ])
              IconButton.filledTonal(
                isSelected: settings.novelTextAlign == option.$1,
                tooltip: option.$1.name,
                icon: Icon(option.$2),
                onPressed: () =>
                    change(() => settings.novelTextAlign = option.$1),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _SettingSection(
        title: 'Typography',
        child: Column(
          children: [
            _novelSlider(
              'Font size',
              settings.novelFontSize.toDouble(),
              8,
              40,
              '${settings.novelFontSize}px',
              (value) => settings.novelFontSize = value.round(),
              divisions: 32,
            ),
            _novelSlider(
              'Padding',
              settings.novelPadding.toDouble(),
              0,
              50,
              '${settings.novelPadding}px',
              (value) => settings.novelPadding = value.round(),
              divisions: 50,
            ),
            _novelSlider(
              'Line height',
              settings.novelLineHeight,
              1,
              3,
              settings.novelLineHeight.toStringAsFixed(1),
              (value) => settings.novelLineHeight = value,
              divisions: 20,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _generalTab() => Column(
    children: [
      _novelSwitch('Show scroll percentage', settings.novelShowPercentage, (
        value,
      ) {
        settings.novelShowPercentage = value;
      }),
      _novelSwitch(
        'Remove extra paragraph spacing',
        settings.novelCompactParagraphs,
        (value) => settings.novelCompactParagraphs = value,
      ),
      _novelSwitch(
        'Use tap zones to scroll',
        settings.novelTapToScroll,
        (value) => settings.novelTapToScroll = value,
      ),
      _novelSwitch(
        'Auto-scroll',
        settings.novelAutoScroll,
        (value) => settings.novelAutoScroll = value,
        secondary: const Icon(Icons.timer_outlined),
      ),
      if (settings.novelAutoScroll)
        _novelSlider(
          'Auto-scroll speed',
          settings.novelAutoScrollSpeed,
          2,
          30,
          settings.novelAutoScrollSpeed.toStringAsFixed(0),
          (value) => settings.novelAutoScrollSpeed = value,
          divisions: 28,
        ),
    ],
  );

  Widget _ttsTab() => Column(
    children: [
      _SettingSection(
        title: 'Speech rate',
        child: _novelSlider(
          'Rate',
          settings.ttsRate,
          .1,
          1,
          '${(settings.ttsRate * 2).toStringAsFixed(1)}x',
          (value) => settings.ttsRate = value,
          divisions: 9,
        ),
      ),
      const SizedBox(height: 16),
      _SettingSection(
        title: 'Pitch',
        child: _novelSlider(
          'Pitch',
          settings.ttsPitch,
          .5,
          2,
          settings.ttsPitch.toStringAsFixed(1),
          (value) => settings.ttsPitch = value,
          divisions: 15,
        ),
      ),
    ],
  );

  Widget _novelSwitch(
    String title,
    bool value,
    ValueChanged<bool> update, {
    Widget? secondary,
  }) => SwitchListTile(
    title: Text(title),
    secondary: secondary,
    value: value,
    onChanged: (value) => change(() => update(value)),
  );

  Widget _novelSlider(
    String title,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> update, {
    required int divisions,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('$title: $display'),
    subtitle: Slider(
      min: min,
      max: max,
      divisions: divisions,
      value: value.clamp(min, max),
      label: display,
      onChanged: (value) => change(() => update(value)),
    ),
  );
}

class _DropdownSetting<T> extends StatelessWidget {
  const _DropdownSetting({
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: DropdownButton<T>(
      value: value,
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text(label(option))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(title),
      Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    ],
  );
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 75,
      height: 70,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.withValues(alpha: .4),
          width: selected ? 3 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Aa',
            style: TextStyle(
              color: foreground,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: TextStyle(color: foreground, fontSize: 11)),
        ],
      ),
    ),
  );
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  static const _colors = [
    Colors.white,
    Colors.black,
    Color(0xff292832),
    Color(0xfff5e6d3),
    Color(0xff5f4b32),
    Color(0xffcccccc),
    Color(0xff424242),
    Color(0xffe0e0e0),
    Color(0xffd7ccc8),
    Color(0xffbbdefb),
    Color(0xffc8e6c9),
    Color(0xffffecb3),
  ];

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Select $label color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _colors)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  onChanged(option);
                  Navigator.pop(dialogContext);
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: option,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: option.toARGB32() == color.toARGB32()
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      width: option.toARGB32() == color.toARGB32() ? 3 : 1,
                    ),
                  ),
                  child: option.toARGB32() == color.toARGB32()
                      ? Icon(
                          Icons.check_circle,
                          color: option.computeLuminance() > .5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          const Icon(Icons.palette_outlined, size: 20),
        ],
      ),
    ),
  );
}
