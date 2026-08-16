// Adapted from Mangayomi's player settings tabs and subtitle_setting_widget.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';

import 'player_session.dart';
import 'player_source.dart';
import '../subtitles/open_subtitles.dart';

Future<void> showPlayerSettings(
  BuildContext context, {
  required PlayerSession session,
  required ValueChanged<PlayerQuality> onQuality,
  required ValueChanged<double> onRate,
  required VoidCallback onFit,
  required double subtitleSize,
  required double subtitleBackgroundOpacity,
  required ValueChanged<double> onSubtitleSize,
  required ValueChanged<double> onSubtitleBackgroundOpacity,
}) async {
  final player = session.player;
  final wasPlaying = player.state.playing;
  await player.pause();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
    builder: (context) => DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Quality'),
                Tab(text: 'Subtitles'),
                Tab(text: 'Audio'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _QualityTab(session: session, onQuality: onQuality),
                  _SubtitleTab(
                    session: session,
                    subtitleSize: subtitleSize,
                    subtitleBackgroundOpacity: subtitleBackgroundOpacity,
                    onSubtitleSize: onSubtitleSize,
                    onSubtitleBackgroundOpacity: onSubtitleBackgroundOpacity,
                  ),
                  _AudioTab(session: session),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<double>(
                    tooltip: 'Playback speed',
                    icon: const Icon(Icons.speed),
                    onSelected: onRate,
                    itemBuilder: (_) => _speeds
                        .map(
                          (speed) => PopupMenuItem(
                            value: speed,
                            child: Text('${speed}x'),
                          ),
                        )
                        .toList(),
                  ),
                  IconButton(
                    tooltip: 'Fit mode',
                    onPressed: onFit,
                    icon: const Icon(Icons.fit_screen),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (wasPlaying) await player.play();
}

const _speeds = [.25, .5, .75, 1.0, 1.25, 1.5, 1.75, 2.0];

class _QualityTab extends StatelessWidget {
  const _QualityTab({required this.session, required this.onQuality});
  final PlayerSession session;
  final ValueChanged<PlayerQuality> onQuality;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
    children: [
      for (final quality in session.source.qualities)
        ListTile(
          title: Text(quality.label),
          selected:
              identical(session.quality, quality) ||
              session.quality?.url == quality.url,
          trailing: session.quality?.url == quality.url
              ? const Icon(Icons.check)
              : null,
          onTap: () {
            Navigator.pop(context);
            onQuality(quality);
          },
        ),
    ],
  );
}

class _SubtitleTab extends StatefulWidget {
  const _SubtitleTab({
    required this.session,
    required this.subtitleSize,
    required this.subtitleBackgroundOpacity,
    required this.onSubtitleSize,
    required this.onSubtitleBackgroundOpacity,
  });
  final PlayerSession session;
  final double subtitleSize;
  final double subtitleBackgroundOpacity;
  final ValueChanged<double> onSubtitleSize;
  final ValueChanged<double> onSubtitleBackgroundOpacity;
  @override
  State<_SubtitleTab> createState() => _SubtitleTabState();
}

class _SubtitleTabState extends State<_SubtitleTab> {
  static const _sizes = [
    20.0,
    24.0,
    28.0,
    32.0,
    36.0,
    40.0,
    48.0,
    56.0,
    64.0,
    72.0,
    84.0,
  ];
  static const _opacities = [0.0, .25, .5, .75, 1.0];
  late double _delay = widget.session.subtitleDelay;
  late double _speed = widget.session.subtitleSpeed;
  late double _size = widget.subtitleSize;
  late double _backgroundOpacity = widget.subtitleBackgroundOpacity;
  bool _searching = false;

  Future<void> _setDelay(double value) async {
    await widget.session.setSubtitleDelay(value);
    if (mounted) setState(() => _delay = value);
  }

  Future<void> _setSpeed(double value) async {
    final speed = value.clamp(.1, 10).toDouble();
    await widget.session.setSubtitleSpeed(speed);
    if (mounted) setState(() => _speed = speed);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Track>(
    stream: widget.session.player.stream.track,
    initialData: widget.session.player.state.track,
    builder: (context, selectedSnapshot) => StreamBuilder<Tracks>(
      stream: widget.session.player.stream.tracks,
      initialData: widget.session.player.state.tracks,
      builder: (context, snapshot) {
        final tracks = widget.session.subtitleTracks(
          snapshot.data ?? const Tracks(),
        );
        final current = selectedSubtitleTrack(
          tracks,
          (selectedSnapshot.data ?? const Track()).subtitle,
        );
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Subtitle delay')),
                IconButton(
                  onPressed: () => _setDelay(_delay - 50),
                  icon: const Icon(Icons.remove_circle),
                ),
                Text('${_delay.round()} ms'),
                IconButton(
                  onPressed: () => _setDelay(_delay + 50),
                  icon: const Icon(Icons.add_circle),
                ),
                IconButton(
                  onPressed: () async {
                    await _setDelay(0);
                    await _setSpeed(1);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Subtitle speed')),
                IconButton(
                  onPressed: () => _setSpeed(_speed - .01),
                  icon: const Icon(Icons.remove_circle),
                ),
                Text(_speed.toStringAsFixed(2)),
                IconButton(
                  onPressed: () => _setSpeed(_speed + .01),
                  icon: const Icon(Icons.add_circle),
                ),
              ],
            ),
            _SnapSlider(
              label: 'Subtitle size',
              value: _size,
              values: _sizes,
              valueLabel: '${_size.round()} px',
              onChanged: (value) {
                setState(() => _size = value);
                widget.onSubtitleSize(value);
              },
            ),
            _SnapSlider(
              label: 'Background opacity',
              value: _backgroundOpacity,
              values: _opacities,
              valueLabel: '${(_backgroundOpacity * 100).round()}%',
              onChanged: (value) {
                setState(() => _backgroundOpacity = value);
                widget.onSubtitleBackgroundOpacity(value);
              },
            ),
            const Divider(),
            for (final track in _uniqueSubtitles(tracks))
              ListTile(
                title: Text(_subtitleLabel(track)),
                selected: isSubtitleTrackActive(track, current),
                trailing: isSubtitleTrackActive(track, current)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  widget.session.player.setSubtitleTrack(track);
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.file_open),
              title: const Text('Load own subtitles'),
              onTap: () async {
                final result = await FilePicker.pickFiles(allowMultiple: false);
                final path = result?.files.first.path;
                if (path != null)
                  await widget.session.player.setSubtitleTrack(
                    SubtitleTrack.uri(path),
                  );
                if (context.mounted) Navigator.pop(context);
              },
            ),
            if (widget.session.source.onSearchSubtitleMedia != null &&
                widget.session.source.onSearchSubtitles != null)
              ListTile(
                leading: _searching
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore),
                title: const Text('Online subtitles'),
                subtitle: const Text('OpenSubtitles'),
                enabled: !_searching,
                onTap: _searchOnline,
              ),
          ],
        );
      },
    ),
  );

  Future<void> _searchOnline() async {
    final input = await _subtitleQuery();
    if (input == null || !mounted) return;
    setState(() => _searching = true);
    try {
      final matches = await widget.session.source.onSearchSubtitleMedia!(
        input.title,
        input.series,
      );
      if (!mounted) return;
      if (matches.isEmpty) {
        showFToast(
          context: context,
          title: const Text('No matching movies or shows found.'),
          alignment: .topRight,
        );
        return;
      }
      final media = await _chooseSubtitleMedia(matches);
      if (media == null || !mounted) return;
      final sources = await widget.session.source.onSearchSubtitles!(
        media,
        input.language,
        input.season,
        input.episode,
      );
      if (!mounted) return;
      if (sources.isEmpty) {
        showFToast(
          context: context,
          title: const Text('No subtitles found in the selected language.'),
          alignment: .topRight,
        );
        return;
      }
      final source = await showFDialog<PlayerSubtitleSource>(
        context: context,
        builder: (dialogContext, _, animation) => FDialog(
          animation: animation,
          semanticsLabel: 'OpenSubtitles results',
          builder: (_, _) => SizedBox(
            width: 420,
            height: 480,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'OpenSubtitles',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView(
                      children: [
                        for (final source in sources)
                          ListTile(
                            leading: const Icon(Icons.subtitles),
                            title: Text(source.label),
                            onTap: () => Navigator.pop(dialogContext, source),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (source != null) {
        final url = source.resolveUrl == null
            ? source.url
            : await source.resolveUrl!();
        if (!mounted) return;
        await widget.session.player.setSubtitleTrack(
          SubtitleTrack.uri(
            url,
            title: source.label,
            language: source.language,
          ),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text(error.toString().replaceFirst('Bad state: ', '')),
          alignment: .topRight,
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<_SubtitleSearchInput?> _subtitleQuery() {
    var query =
        widget.session.source.subtitleSearchQuery ??
        widget.session.source.title;
    var series = widget.session.source.subtitleSearchSeries;
    var season = widget.session.source.subtitleSearchSeason.toString();
    var episode = widget.session.source.subtitleSearchEpisode.toString();
    var language = widget.session.source.subtitleSearchLanguage;
    return showFDialog<_SubtitleSearchInput>(
      context: context,
      builder: (dialogContext, _, animation) => FDialog(
        animation: animation,
        semanticsLabel: 'Search OpenSubtitles',
        builder: (_, _) => StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final parsedSeason = int.tryParse(season);
              final parsedEpisode = int.tryParse(episode);
              if (query.trim().isEmpty ||
                  (series &&
                      (parsedSeason == null ||
                          parsedSeason < 0 ||
                          parsedEpisode == null ||
                          parsedEpisode < 1))) {
                return;
              }
              Navigator.pop(
                dialogContext,
                _SubtitleSearchInput(
                  title: query.trim(),
                  series: series,
                  language: language,
                  season: series ? parsedSeason! : 1,
                  episode: series ? parsedEpisode! : 1,
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search OpenSubtitles',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FTextField(
                    control: FTextFieldControl.managed(
                      initial: TextEditingValue(
                        text: query,
                        selection: TextSelection.collapsed(
                          offset: query.length,
                        ),
                      ),
                      onChange: (value) => query = value.text,
                    ),
                    autofocus: true,
                    label: const Text('Movie or show title'),
                    onSubmit: (_) => submit(),
                  ),
                  const SizedBox(height: 12),
                  FSelect<bool>(
                    label: const Text('Type'),
                    items: const {'Series': true, 'Movie': false},
                    control: .lifted(
                      value: series,
                      onChange: (value) =>
                          setDialogState(() => series = value ?? true),
                    ),
                  ),
                  if (series) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FTextField(
                            control: FTextFieldControl.managed(
                              initial: TextEditingValue(text: season),
                              onChange: (value) => season = value.text,
                            ),
                            keyboardType: TextInputType.number,
                            label: const Text('Season'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FTextField(
                            control: FTextFieldControl.managed(
                              initial: TextEditingValue(text: episode),
                              onChange: (value) => episode = value.text,
                            ),
                            keyboardType: TextInputType.number,
                            label: const Text('Episode'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  FSelect<String>(
                    label: const Text('Language'),
                    items: subtitleLanguages,
                    control: .lifted(
                      value: language,
                      onChange: (value) => language = value ?? language,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FButton(
                        variant: .outline,
                        mainAxisSize: .min,
                        onPress: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FButton(
                        mainAxisSize: .min,
                        onPress: submit,
                        child: const Text('Search'),
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
  }

  Future<PlayerSubtitleMedia?> _chooseSubtitleMedia(
    List<PlayerSubtitleMedia> matches,
  ) => showFDialog<PlayerSubtitleMedia>(
    context: context,
    builder: (dialogContext, _, animation) => FDialog(
      animation: animation,
      semanticsLabel: 'Select movie or show',
      builder: (_, _) => SizedBox(
        width: 440,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select movie or show',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  children: [
                    for (final media in matches)
                      ListTile(
                        leading: media.posterUrl == null
                            ? const Icon(Icons.movie_outlined)
                            : Image.network(
                                media.posterUrl!,
                                width: 36,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.movie_outlined),
                              ),
                        title: Text(media.title),
                        subtitle: Text(
                          '${media.series ? 'Series' : 'Movie'}${media.year == null ? '' : ' · ${media.year}'}',
                        ),
                        onTap: () => Navigator.pop(dialogContext, media),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SubtitleSearchInput {
  const _SubtitleSearchInput({
    required this.title,
    required this.series,
    required this.language,
    required this.season,
    required this.episode,
  });

  final String title;
  final bool series;
  final String language;
  final int season;
  final int episode;
}

class _AudioTab extends StatelessWidget {
  const _AudioTab({required this.session});
  final PlayerSession session;
  @override
  Widget build(BuildContext context) => StreamBuilder<Track>(
    stream: session.player.stream.track,
    initialData: session.player.state.track,
    builder: (context, selectedSnapshot) => StreamBuilder<Tracks>(
      stream: session.player.stream.tracks,
      initialData: session.player.state.tracks,
      builder: (context, snapshot) {
        final tracks = session.audioTracks(snapshot.data ?? const Tracks());
        final current = selectedAudioTrack(
          tracks,
          (selectedSnapshot.data ?? const Track()).audio,
        );
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          children: tracks.isEmpty
              ? const [ListTile(title: Text('No audio tracks'))]
              : [
                  for (final track in tracks)
                    ListTile(
                      title: Text(
                        playerTrackLabel(
                          id: track.id,
                          title: track.title,
                          language: track.language,
                        ),
                      ),
                      selected: isAudioTrackActive(track, current),
                      trailing: isAudioTrackActive(track, current)
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        session.player.setAudioTrack(track);
                        Navigator.pop(context);
                      },
                    ),
                ],
        );
      },
    ),
  );
}

class _SnapSlider extends StatelessWidget {
  const _SnapSlider({
    required this.label,
    required this.value,
    required this.values,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<double> values;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(value);
    return Row(
      children: [
        Expanded(child: Text(label)),
        Expanded(
          flex: 2,
          child: Slider(
            value: (index < 0 ? 0 : index).toDouble(),
            max: (values.length - 1).toDouble(),
            divisions: values.length - 1,
            onChanged: (index) => onChanged(values[index.round()]),
          ),
        ),
        SizedBox(width: 50, child: Text(valueLabel, textAlign: TextAlign.end)),
      ],
    );
  }
}

List<SubtitleTrack> _uniqueSubtitles(List<SubtitleTrack> tracks) {
  final labels = <String>{};
  return tracks.where((track) => labels.add(_subtitleLabel(track))).toList();
}

String _subtitleLabel(SubtitleTrack track) => track.id == 'no'
    ? 'None'
    : playerTrackLabel(
        id: track.id,
        title: track.title,
        language: track.language,
      );
