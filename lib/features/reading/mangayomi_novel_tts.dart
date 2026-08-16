// Adapted from Mangayomi's novel_tts_service.dart and tts_player_bar.dart.
// Source: https://github.com/kodjodevf/mangayomi
// Licensed under the Apache License, Version 2.0.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:html/parser.dart' as html_parser;

import 'mangayomi_reader_settings.dart';

enum _TtsState { stopped, playing, paused }

/// Reading position of the TTS player, keyed to the reader's HTML blocks.
class TtsParagraphProgress {
  const TtsParagraphProgress({
    required this.blockIndex,
    this.wordStart = -1,
    this.wordEnd = -1,
  });

  final int blockIndex;
  final int wordStart;
  final int wordEnd;
}

/// A compact player for reading novel HTML one block at a time.
class MangayomiNovelTtsBar extends StatefulWidget {
  const MangayomiNovelTtsBar({
    super.key,
    required this.blocks,
    required this.settings,
    this.onParagraphChanged,
    this.onWordProgress,
    required this.onClose,
  });

  /// HTML fragments of the chapter, one per scrollable block.
  final List<String> blocks;
  final MangayomiReaderSettings settings;

  /// Fires when the active paragraph (block) changes.
  final ValueChanged<int>? onParagraphChanged;

  /// Fires as the engine advances through the words of a paragraph.
  final ValueChanged<TtsParagraphProgress>? onWordProgress;
  final VoidCallback onClose;

  @override
  State<MangayomiNovelTtsBar> createState() => _MangayomiNovelTtsBarState();
}

class _MangayomiNovelTtsBarState extends State<MangayomiNovelTtsBar> {
  static const _manualInterruptionWindow = Duration(milliseconds: 500);
  static final _whitespace = RegExp(r'\s');

  FlutterTts? _tts;
  List<String> _paragraphs = const [];
  List<int> _blockIndices = const [];
  _TtsState _state = _TtsState.stopped;
  int _currentIndex = 0;
  int _resumeOffset = 0;
  int _utteranceOffset = 0;
  int _wordStart = -1;
  int _wordEnd = -1;
  bool _pausedNatively = false;
  bool? _available;
  DateTime? _manualInterruptionUntil;
  double? _appliedRate;
  double? _appliedPitch;
  String? _appliedLanguage;

  bool get _platformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  bool get _isManualInterruptionActive {
    final until = _manualInterruptionUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  void initState() {
    super.initState();
    _initParagraphs();
    if (!_platformSupported || _paragraphs.isEmpty) {
      _available = false;
      return;
    }
    unawaited(_initializeAndPlay());
  }

  @override
  void didUpdateWidget(covariant MangayomiNovelTtsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.blocks, oldWidget.blocks)) {
      _initParagraphs();
      _currentIndex = 0;
      _run(_restart());
    } else if (_available == true &&
        (_appliedRate != widget.settings.ttsRate ||
            _appliedPitch != widget.settings.ttsPitch ||
            _appliedLanguage != widget.settings.ttsLanguage)) {
      _run(_applySettings());
    }
  }

  void _initParagraphs() {
    final paragraphs = <String>[];
    final blockIndices = <int>[];
    for (var i = 0; i < widget.blocks.length; i++) {
      final text = _blockText(widget.blocks[i]);
      if (text.isEmpty) continue;
      paragraphs.add(text);
      blockIndices.add(i);
    }
    _paragraphs = paragraphs;
    _blockIndices = blockIndices;
  }

  static String _blockText(String fragment) =>
      html_parser.parseFragment(fragment).text?.trim() ?? '';

  static int _paragraphWordEnd(String paragraph, int wordStart) {
    if (wordStart < 0 || wordStart >= paragraph.length) return wordStart;
    var end = wordStart;
    while (end < paragraph.length && !_whitespace.hasMatch(paragraph[end])) {
      end++;
    }
    return end;
  }

  Future<void> _initializeAndPlay() async {
    try {
      final tts = FlutterTts();
      _tts = tts;
      tts.setCompletionHandler(_onParagraphComplete);
      tts.setCancelHandler(() {
        if (!_isManualInterruptionActive) _setState(_TtsState.stopped);
      });
      tts.setErrorHandler((_) => _fail());
      tts.setProgressHandler((text, start, end, word) {
        if (_state != _TtsState.playing) return;
        _wordStart = start + _utteranceOffset;
        _wordEnd = _paragraphWordEnd(_paragraphs[_currentIndex], _wordStart);
        widget.onWordProgress?.call(
          TtsParagraphProgress(
            blockIndex: _blockIndices[_currentIndex],
            wordStart: _wordStart,
            wordEnd: _wordEnd,
          ),
        );
      });
      await tts.awaitSpeakCompletion(true);
      await _applySettings();
      if (!mounted) return;
      setState(() => _available = true);
      await _playCurrent();
    } on Object {
      _fail();
    }
  }

  Future<void> _applySettings() async {
    final tts = _tts;
    if (tts == null) return;
    await tts.setSpeechRate(widget.settings.ttsRate);
    await tts.setPitch(widget.settings.ttsPitch);
    final language = widget.settings.ttsLanguage;
    if (language != null && language.isNotEmpty) {
      await tts.setLanguage(language);
    }
    _appliedRate = widget.settings.ttsRate;
    _appliedPitch = widget.settings.ttsPitch;
    _appliedLanguage = language;
  }

  Future<void> _restart() async {
    if (_paragraphs.isEmpty || !_platformSupported) {
      await _stopSpeech();
      if (mounted) setState(() => _available = false);
      return;
    }
    if (_tts == null) {
      await _initializeAndPlay();
      return;
    }
    await _stopSpeech();
    _resetProgress();
    if (mounted) setState(() => _available = true);
    await _playCurrent();
  }

  Future<void> _playCurrent({int? fromOffset}) async {
    final tts = _tts;
    if (tts == null || _paragraphs.isEmpty || !mounted) return;
    final paragraph = _paragraphs[_currentIndex];
    final offset = (fromOffset ?? _resumeOffset).clamp(0, paragraph.length);
    if (offset == paragraph.length) {
      _onParagraphComplete();
      return;
    }
    _utteranceOffset = offset;
    _resumeOffset = offset;
    _setState(_TtsState.playing);
    widget.onParagraphChanged?.call(_blockIndices[_currentIndex]);
    await tts.speak(paragraph.substring(offset));
  }

  void _onParagraphComplete() {
    if (!mounted ||
        _state != _TtsState.playing ||
        _isManualInterruptionActive) {
      return;
    }
    if (_currentIndex == _paragraphs.length - 1) {
      _setState(_TtsState.stopped);
      return;
    }
    setState(() => _currentIndex++);
    _resetProgress();
    _run(_playCurrent());
  }

  Future<void> _togglePlayback() async {
    final tts = _tts;
    if (tts == null) return;
    try {
      if (_state == _TtsState.playing) {
        if (_wordStart >= 0) _resumeOffset = _wordStart;
        _setState(_TtsState.paused);
        final result = await tts.pause();
        _pausedNatively = result == 1;
        if (!_pausedNatively) await _stopSpeech();
      } else if (_state == _TtsState.paused) {
        _setState(_TtsState.playing);
        widget.onParagraphChanged?.call(_blockIndices[_currentIndex]);
        if (_pausedNatively) {
          _pausedNatively = false;
          await tts.speak(
            _paragraphs[_currentIndex].substring(_utteranceOffset),
          );
        } else {
          await _playCurrent(fromOffset: _resumeOffset);
        }
      } else {
        await _playCurrent();
      }
    } on Object {
      _fail();
    }
  }

  Future<void> _skip(int delta) async {
    final target = _currentIndex + delta;
    if (target < 0 || target >= _paragraphs.length) return;
    try {
      final wasPlaying = _state == _TtsState.playing;
      await _stopSpeech();
      if (!mounted) return;
      setState(() => _currentIndex = target);
      _resetProgress();
      widget.onParagraphChanged?.call(_blockIndices[_currentIndex]);
      if (wasPlaying) await _playCurrent();
    } on Object {
      _fail();
    }
  }

  Future<void> _stop() async {
    _setState(_TtsState.stopped);
    try {
      await _stopSpeech();
    } on Object {
      // Closing the player must still work when the platform TTS fails.
    }
    if (mounted) widget.onClose();
  }

  Future<void> _stopSpeech() async {
    _manualInterruptionUntil = DateTime.now().add(_manualInterruptionWindow);
    await _tts?.stop();
  }

  void _resetProgress() {
    _resumeOffset = 0;
    _utteranceOffset = 0;
    _wordStart = -1;
    _wordEnd = -1;
    _pausedNatively = false;
  }

  void _setState(_TtsState state) {
    if (!mounted || _state == state) return;
    setState(() => _state = state);
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _available = false;
      _state = _TtsState.stopped;
    });
  }

  void _run(Future<void> future) {
    unawaited(future.catchError((Object _) => _fail()));
  }

  @override
  void dispose() {
    unawaited(_tts?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_available == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (_available == false) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Expanded(child: Text('Text-to-speech unavailable')),
            IconButton(
              onPressed: _stop,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ],
        ),
      );
    }
    final total = _paragraphs.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: ((_currentIndex + 1) / total).clamp(0.0, 1.0),
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paragraph ${_currentIndex + 1} of $total',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: _currentIndex == 0 ? null : () => _skip(-1),
                  icon: const Icon(Icons.skip_previous_rounded),
                  tooltip: 'Previous paragraph',
                ),
                IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _state == _TtsState.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  color: theme.colorScheme.primary,
                  tooltip: _state == _TtsState.playing ? 'Pause' : 'Play',
                ),
                IconButton(
                  onPressed: _currentIndex == total - 1 ? null : () => _skip(1),
                  icon: const Icon(Icons.skip_next_rounded),
                  tooltip: 'Next paragraph',
                ),
                IconButton(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded),
                  tooltip: 'Stop',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
