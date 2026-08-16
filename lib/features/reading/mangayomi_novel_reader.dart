// Ported from Mangayomi's novel reader, Apache-2.0.
// https://github.com/kodjodevf/mangayomi/blob/main/lib/modules/novel/novel_reader_view.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'mangayomi_novel_tts.dart';
import 'mangayomi_reader_settings.dart';
import 'mangayomi_reader_settings_sheet.dart';

class MangayomiNovelReader extends StatefulWidget {
  const MangayomiNovelReader({
    super.key,
    required this.title,
    required this.chapterTitle,
    required this.html,
    required this.settings,
    required this.initialProgress,
    required this.onProgress,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onChapterList,
  });

  final String title;
  final String chapterTitle;
  final String html;
  final MangayomiReaderSettings settings;
  final double initialProgress;
  final ValueChanged<double> onProgress;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onChapterList;

  @override
  State<MangayomiNovelReader> createState() => _MangayomiNovelReaderState();
}

class _MangayomiNovelReaderState extends State<MangayomiNovelReader>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Timer? _autoScrollTimer;
  bool _controlsVisible = false;
  bool _showTts = false;
  bool _fullscreen = true;
  final ValueNotifier<double> _position = ValueNotifier(0);
  final ValueNotifier<int?> _activeBlock = ValueNotifier(null);
  final ValueNotifier<TtsParagraphProgress?> _wordProgress = ValueNotifier(null);
  late List<String> _blocks = const [];
  final List<GlobalKey> _blockKeys = [];

  MangayomiReaderSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _rebuildBlocks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restorePosition();
      _applyWakeLock();
      _syncAutoScroll();
      _setSystemUi(false);
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant MangayomiNovelReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _rebuildBlocks();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restorePosition();
      });
    }
  }

  void _rebuildBlocks() {
    _blocks = _splitHtmlBlocks(widget.html);
    _blockKeys
      ..clear()
      ..addAll(List.generate(_blocks.length, (_) => GlobalKey()));
    _activeBlock.value = null;
    _wordProgress.value = null;
  }

  void _restorePosition() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      (_scroll.position.maxScrollExtent * widget.initialProgress).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    final next = (_scroll.offset / _scroll.position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    if ((next - _position.value).abs() < .001) return;
    _position.value = next;
    widget.onProgress(next);
  }

  void _scrollBy(double value) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (_scroll.offset + value).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
  }

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!settings.novelAutoScroll) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_scroll.hasClients) return;
      if (_scroll.offset >= _scroll.position.maxScrollExtent) {
        _autoScrollTimer?.cancel();
        return;
      }
      _scroll.jumpTo(
        min(
          _scroll.position.maxScrollExtent,
          _scroll.offset + settings.novelAutoScrollSpeed / 4,
        ),
      );
    });
  }

  Future<void> _applyWakeLock() async {
    try {
      if (settings.keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on PlatformException {
      // The reader remains usable when a runner lacks wake-lock support.
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _setSystemUi(_controlsVisible);
  }

  Future<void> _setSystemUi(bool visible) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) return;
    await SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersive,
    );
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.setFullScreen(_fullscreen);
    } else {
      await _setSystemUi(!_fullscreen);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      Navigator.maybePop(context);
    } else if (key == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullscreen());
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      _scrollBy(-100);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _scrollBy(100);
    } else if (key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.pageDown) {
      widget.onNextChapter?.call();
    } else if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.pageUp) {
      widget.onPreviousChapter?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyWakeLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _focusNode.dispose();
    _position.dispose();
    _activeBlock.dispose();
    _wordProgress.dispose();
    unawaited(_disableWakeLock());
    unawaited(_setSystemUi(true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    onKeyEvent: _onKey,
    child: Scaffold(
      backgroundColor: settings.novelBackground,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          if (settings.novelTapToScroll) ...[
            Positioned.fill(child: _leftRightZones()),
            Positioned.fill(child: _topBottomZones()),
          ] else
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
              ),
            ),
          _appBar(),
          _bottomBar(),
          if (_showTts || (settings.novelShowPercentage && !_controlsVisible))
            Positioned(
              left: 0,
              right: 0,
              bottom: _controlsVisible ? 140 : 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showTts)
                      MangayomiNovelTtsBar(
                        blocks: _blocks,
                        settings: settings,
                        onParagraphChanged: _onTtsParagraph,
                        onWordProgress: _onTtsWord,
                        onClose: () => setState(() {
                          _showTts = false;
                          _activeBlock.value = null;
                          _wordProgress.value = null;
                        }),
                      ),
                    if (settings.novelShowPercentage && !_controlsVisible)
                      Container(
                        width: double.infinity,
                        color: settings.novelBackground.withValues(alpha: .9),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _position,
                          builder: (_, value, _) => Text(
                            '${(value * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: settings.novelTextColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _content() {
    final horizontal = MediaQuery.sizeOf(context).width >= 900
        ? max(100.0, settings.novelPadding.toDouble())
        : settings.novelPadding.toDouble();
    return SingleChildScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              for (var i = 0; i < _blocks.length; i++)
                KeyedSubtree(
                  key: _blockKeys[i],
                  child: _block(i),
                ),
              const SizedBox(height: 150),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(int i) {
    final primary = Theme.of(context).colorScheme.primary;
    final light = primary.withValues(alpha: .06);
    return ValueListenableBuilder<int?>(
      valueListenable: _activeBlock,
      builder: (context, activeIndex, _) {
        final isActive = activeIndex == i;
        final block = _blocks[i];
        return Container(
          decoration: isActive
              ? BoxDecoration(
                  color: light,
                  border: Border(left: BorderSide(color: primary, width: 3)),
                )
              : null,
          padding: isActive ? const EdgeInsets.only(left: 8) : null,
          child: isActive
              ? ValueListenableBuilder<TtsParagraphProgress?>(
                  valueListenable: _wordProgress,
                  builder: (context, progress, _) => Html(
                    data: progress != null &&
                            progress.wordEnd > progress.wordStart
                        ? _withWordHighlight(
                              block,
                              progress.wordStart,
                              progress.wordEnd,
                            ) ??
                            block
                        : block,
                    style: _htmlStyles(light),
                  ),
                )
              : Html(data: block, style: _htmlStyles()),
        );
      },
    );
  }

  Map<String, Style> _htmlStyles([Color? activeBackground]) {
    final primary = Theme.of(context).colorScheme.primary;
    final align = switch (settings.novelTextAlign) {
      NovelTextAlign.left => TextAlign.left,
      NovelTextAlign.center => TextAlign.center,
      NovelTextAlign.right => TextAlign.right,
      NovelTextAlign.justify => TextAlign.justify,
    };
    final paragraphMargin = settings.novelCompactParagraphs ? 4.0 : 8.0;
    final background = activeBackground ?? settings.novelBackground;
    final base = Style(
      color: settings.novelTextColor,
      backgroundColor: background,
      fontFamily: 'Merriweather',
      fontSize: FontSize(settings.novelFontSize.toDouble()),
      lineHeight: LineHeight.number(settings.novelLineHeight),
      textAlign: align,
      margin: Margins.only(bottom: paragraphMargin),
    );
    return {
      'body': base.copyWith(margin: Margins.zero, padding: HtmlPaddings.zero),
      'p': base,
      'div': base,
      'li': base,
      'blockquote': base.copyWith(
        padding: HtmlPaddings.symmetric(horizontal: 14, vertical: 8),
        border: Border(
          left: BorderSide(color: settings.novelTextColor, width: 3),
        ),
      ),
      'pre': base.copyWith(
        padding: HtmlPaddings.all(12),
        backgroundColor: settings.novelTextColor.withValues(alpha: .08),
      ),
      'code': base.copyWith(fontFamily: 'Geist Mono'),
      'mark': Style(
        backgroundColor: primary.withValues(alpha: .35),
        textDecoration: TextDecoration.underline,
        textDecorationColor: primary,
        color: settings.novelTextColor,
      ),
      'table': base.copyWith(
        border: Border.all(color: settings.novelTextColor),
      ),
      'td': base.copyWith(
        padding: HtmlPaddings.all(6),
        border: Border.all(
          color: settings.novelTextColor.withValues(alpha: .5),
        ),
      ),
      'th': base.copyWith(
        padding: HtmlPaddings.all(6),
        border: Border.all(color: settings.novelTextColor),
        fontWeight: FontWeight.bold,
      ),
      'img': Style(width: Width.auto(), height: Height.auto()),
    };
  }

  Widget _leftRightZones() => Row(
    children: [
      Expanded(
        flex: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _scrollBy(-100),
        ),
      ),
      Expanded(
        flex: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleControls,
        ),
      ),
      Expanded(
        flex: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _scrollBy(100),
        ),
      ),
    ],
  );

  Widget _topBottomZones() => Column(
    children: [
      Expanded(
        flex: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _scrollBy(-100),
        ),
      ),
      const Expanded(flex: 5, child: SizedBox.shrink()),
      Expanded(
        flex: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _scrollBy(100),
        ),
      ),
    ],
  );

  Widget _appBar() => AnimatedPositioned(
    duration: const Duration(milliseconds: 300),
    top: _controlsVisible ? 0 : -110,
    left: 0,
    right: 0,
    child: AppBar(
      backgroundColor: settings.novelBackground.withValues(alpha: .96),
      foregroundColor: settings.novelTextColor,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(widget.chapterTitle, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Chapter list',
          onPressed: widget.onChapterList,
          icon: const Icon(Icons.format_list_numbered),
        ),
      ],
    ),
  );

  Widget _bottomBar() => AnimatedPositioned(
    duration: const Duration(milliseconds: 300),
    bottom: _controlsVisible ? 0 : -150,
    left: 0,
    right: 0,
    height: 140,
    child: Material(
      color: settings.novelBackground.withValues(alpha: .97),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _chapterButton(
                    Icons.skip_previous_rounded,
                    widget.onPreviousChapter,
                  ),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _position,
                      builder: (_, value, _) => Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${(value * 100).round()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              padding: EdgeInsets.zero,
                              value: value,
                              onChanged: (next) {
                                if (_scroll.hasClients) {
                                  _scroll.jumpTo(
                                    _scroll.position.maxScrollExtent * next,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(
                            width: 32,
                            child: Text(
                              '100',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _chapterButton(Icons.skip_next_rounded, widget.onNextChapter),
                ],
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: settings.novelTextColor.withValues(alpha: .35),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Smaller text',
                          onPressed: settings.novelFontSize <= 4
                              ? null
                              : () => _setFont(settings.novelFontSize - 1),
                          icon: const Icon(Icons.text_decrease),
                        ),
                        Text('${settings.novelFontSize}px'),
                        IconButton(
                          tooltip: 'Larger text',
                          onPressed: settings.novelFontSize >= 40
                              ? null
                              : () => _setFont(settings.novelFontSize + 1),
                          icon: const Icon(Icons.text_increase),
                        ),
                      ],
                    ),
                  ),
                  if (!Platform.isLinux)
                    IconButton(
                      tooltip: 'Text to speech',
                      onPressed: () => setState(() => _showTts = !_showTts),
                      icon: Icon(
                        _showTts
                            ? Icons.record_voice_over
                            : Icons.record_voice_over_outlined,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Reader settings',
                    onPressed: () => showMangayomiNovelSettings(
                      context: context,
                      settings: settings,
                      onChanged: () {
                        if (!mounted) return;
                        setState(() {});
                        _applyWakeLock();
                        _syncAutoScroll();
                      },
                    ),
                    icon: const Icon(Icons.settings),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _chapterButton(IconData icon, VoidCallback? callback) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: IconButton(
      onPressed: callback,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
    ),
  );

  void _setFont(int value) {
    setState(() => settings.novelFontSize = value);
    unawaited(settings.save());
  }

  static const double _ttsScrollInset = 50;

  void _onTtsParagraph(int blockIndex) {
    _activeBlock.value = blockIndex;
    _wordProgress.value = null;
    _scrollToParagraph(blockIndex);
  }

  void _onTtsWord(TtsParagraphProgress progress) {
    if (progress.blockIndex != _activeBlock.value) return;
    _wordProgress.value = progress;
  }

  void _scrollToParagraph(int index) {
    if (index < 0 || index >= _blockKeys.length) return;
    final context = _blockKeys[index].currentContext;
    if (context == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return;
    final offset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
    final inset = _ttsScrollInset + MediaQuery.paddingOf(context).top;
    _scroll.animateTo(
      (offset - inset).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  static const _blockSelector =
      'p, h1, h2, h3, h4, h5, h6, li, blockquote, div';

  static List<String> _splitHtmlBlocks(String html) {
    final body = html_parser.parse(html).body;
    if (body == null || body.text.trim().isEmpty) return const [];
    final all = body.querySelectorAll('$_blockSelector, img');
    final allSet = all.toSet();
    final blocks = <String>[];
    final collected = <dom.Element>[];
    for (final element in all) {
      final isImage = element.localName == 'img';
      final text = element.text.trim();
      if (text.isEmpty && !isImage && !_containsImage(element)) continue;
      if (_hasReadableChild(element, allSet)) continue;
      if (_hasAncestorIn(element, collected)) continue;
      blocks.add(element.outerHtml);
      collected.add(element);
    }
    if (blocks.isNotEmpty) return blocks;
    return body.text
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => '<div>$line</div>')
        .toList();
  }

  static bool _hasReadableChild(
    dom.Element element,
    Set<dom.Element> allBlocks,
  ) => element
      .querySelectorAll(_blockSelector)
      .any(
        (child) =>
            child != element &&
            allBlocks.contains(child) &&
            child.text.trim().isNotEmpty,
      );

  static bool _hasAncestorIn(
    dom.Element element,
    List<dom.Element> collected,
  ) {
    var parent = element.parent;
    while (parent != null) {
      if (collected.contains(parent)) return true;
      parent = parent.parent;
    }
    return false;
  }

  static bool _containsImage(dom.Element element) =>
      element.querySelectorAll('img').isNotEmpty;

  static String? _withWordHighlight(
    String block,
    int wordStart,
    int wordEnd,
  ) {
    final fragment = html_parser.parseFragment(block);
    final raw = fragment.text ?? '';
    final trimmed = raw.trim();
    if (trimmed.isEmpty || wordStart < 0 || wordEnd <= wordStart) return null;
    final leading = raw.length - raw.trimLeft().length;
    final rawStart = leading + wordStart;
    if (rawStart < 0 || rawStart >= raw.length) return null;
    final rawEnd = rawStart + (wordEnd - wordStart) > raw.length
        ? raw.length
        : rawStart + (wordEnd - wordStart);
    if (rawEnd <= rawStart) return null;
    final texts = <dom.Text>[];
    void collect(dom.Node node) {
      if (node is dom.Text) {
        texts.add(node);
      } else if (node is dom.Element) {
        for (final child in node.nodes) {
          collect(child);
        }
      }
    }

    for (final child in fragment.nodes) {
      collect(child);
    }
    var pos = 0;
    for (final text in texts) {
      final data = text.data;
      final nodeEnd = pos + data.length;
      if (rawStart >= pos && rawStart < nodeEnd && rawEnd <= nodeEnd) {
        final startInNode = rawStart - pos;
        final endInNode = rawEnd - pos;
        var markStart = startInNode;
        var markEnd = endInNode;
        while (markStart < markEnd &&
            RegExp(r'\s').hasMatch(data[markStart])) {
          markStart++;
        }
        while (markEnd > markStart &&
            RegExp(r'\s').hasMatch(data[markEnd - 1])) {
          markEnd--;
        }
        if (markStart >= markEnd) return null;
        final parent = text.parent;
        if (parent == null) return null;
        final mark = dom.Element.tag('mark');
        mark.text = data.substring(markStart, markEnd);
        final index = parent.nodes.indexOf(text);
        if (index < 0) return null;
        parent.nodes.replaceRange(
          index,
          index + 1,
          [
            dom.Text(data.substring(0, markStart)),
            mark,
            dom.Text(data.substring(markEnd)),
          ],
        );
        return fragment.outerHtml;
      }
      pos = nodeEnd;
    }
    return null;
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
    } on PlatformException {
      // The runner may not register the wake-lock plugin in tests.
    }
  }
}
