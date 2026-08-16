// Ported from Mangayomi's manga reader, Apache-2.0.
// https://github.com/kodjodevf/mangayomi/tree/main/lib/modules/manga/reader

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../widgets/terra_network_image.dart';
import 'mangayomi_reader_gesture_handler.dart';
import 'mangayomi_reader_settings.dart';
import 'mangayomi_reader_settings_sheet.dart';
import 'reading_models.dart';

class MangayomiMangaReader extends StatefulWidget {
  const MangayomiMangaReader({
    super.key,
    required this.title,
    required this.chapterTitle,
    required this.pages,
    required this.settings,
    required this.initialProgress,
    required this.onProgress,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onChapterList,
  });

  final String title;
  final String chapterTitle;
  final List<ReadPage> pages;
  final MangayomiReaderSettings settings;
  final double initialProgress;
  final ValueChanged<double> onProgress;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onChapterList;

  @override
  State<MangayomiMangaReader> createState() => _MangayomiMangaReaderState();
}

class _MangayomiMangaReaderState extends State<MangayomiMangaReader> {
  late final PageController _pageController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final ValueNotifier<int> _currentPage = ValueNotifier(0);
  final FocusNode _focusNode = FocusNode();
  Timer? _autoScrollTimer;
  bool _controlsVisible = false;
  bool _fullscreen = true;
  int _pagedIndex = 0;

  MangayomiReaderSettings get settings => widget.settings;
  int get _pageStep =>
      settings.pageMode == PageMode.doublePage &&
          !settings.mode.isHorizontalContinuous
      ? 2
      : 1;
  int get _displayCount => max(1, (widget.pages.length / _pageStep).ceil());
  int _leadingIndex(int index) => (index ~/ _pageStep) * _pageStep;
  int _trailingIndex(int leading) =>
      min(widget.pages.length - 1, leading + _pageStep - 1);

  @override
  void initState() {
    super.initState();
    _pagedIndex = _leadingIndex(
      (widget.initialProgress * (widget.pages.length - 1)).round(),
    );
    _pageController = PageController(initialPage: _pagedIndex ~/ _pageStep);
    _currentPage.value = _trailingIndex(_pagedIndex);
    _positions.itemPositions.addListener(_continuousPositionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyWakeLock();
      _restoreContinuousPosition();
      _syncAutoScroll();
      _setSystemUi(false);
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant MangayomiMangaReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages != widget.pages) {
      _pagedIndex = _leadingIndex(
        (widget.initialProgress * (widget.pages.length - 1)).round(),
      );
      _currentPage.value = _trailingIndex(_pagedIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_pagedIndex ~/ _pageStep);
        }
        _restoreContinuousPosition();
      });
    }
  }

  void _continuousPositionChanged() {
    if (!settings.mode.isContinuous) return;
    final visible = _positions.itemPositions.value
        .where((item) => item.index < _displayCount)
        .toList();
    if (visible.isEmpty) return;
    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final leading = (visible.first.index * _pageStep).clamp(
      0,
      widget.pages.length - 1,
    );
    final trailing = _trailingIndex(leading);
    if (_pagedIndex == leading && _currentPage.value == trailing) return;
    _pagedIndex = leading;
    _currentPage.value = trailing;
    _report(trailing);
  }

  void _restoreContinuousPosition() {
    if (!settings.mode.isContinuous || !_itemScrollController.isAttached) {
      return;
    }
    _itemScrollController.jumpTo(
      index: (_pagedIndex ~/ _pageStep).clamp(0, _displayCount - 1),
    );
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

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!settings.mode.isContinuous || !settings.autoScroll) return;
    final milliseconds = (3200 / settings.autoScrollSpeed).round().clamp(
      90,
      1000,
    );
    _autoScrollTimer = Timer.periodic(Duration(milliseconds: milliseconds), (
      _,
    ) {
      if (!_itemScrollController.isAttached) return;
      final next = (_pagedIndex + _pageStep).clamp(0, widget.pages.length);
      if (next >= widget.pages.length) {
        _autoScrollTimer?.cancel();
        return;
      }
      _itemScrollController.scrollTo(
        index: next ~/ _pageStep,
        duration: Duration(milliseconds: milliseconds * 2),
        curve: Curves.linear,
      );
    });
  }

  void _report(int index) {
    final denominator = max(1, widget.pages.length - 1);
    widget.onProgress(index / denominator);
  }

  void _setPage(int rawIndex, {bool animate = true}) {
    final index = _leadingIndex(rawIndex.clamp(0, widget.pages.length - 1));
    final trailing = _trailingIndex(index);
    _pagedIndex = index;
    _currentPage.value = trailing;
    _report(trailing);
    if (settings.mode.isContinuous) {
      if (_itemScrollController.isAttached) {
        if (animate) {
          _itemScrollController.scrollTo(
            index: index ~/ _pageStep,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _itemScrollController.jumpTo(index: index ~/ _pageStep);
        }
      }
    } else if (_pageController.hasClients) {
      final page = index ~/ _pageStep;
      if (animate && settings.animatePageTransitions) {
        _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _pageController.jumpToPage(page);
      }
    }
  }

  void _previousPage() {
    if (_pagedIndex <= 0) {
      widget.onPreviousChapter?.call();
    } else {
      _setPage(_pagedIndex - _pageStep);
    }
  }

  void _nextPage() {
    if (_pagedIndex + _pageStep >= widget.pages.length) {
      widget.onNextChapter?.call();
    } else {
      _setPage(_pagedIndex + _pageStep);
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
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _previousPage();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nextPage();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      settings.mode.isRTL ? _nextPage() : _previousPage();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      settings.mode.isRTL ? _previousPage() : _nextPage();
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
  void dispose() {
    _autoScrollTimer?.cancel();
    _positions.itemPositions.removeListener(_continuousPositionChanged);
    _pageController.dispose();
    _currentPage.dispose();
    _focusNode.dispose();
    unawaited(_disableWakeLock());
    unawaited(_setSystemUi(true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = settings.background.resolve(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: [
            Positioned.fill(child: _gallery(background)),
            Positioned.fill(
              child: MangayomiReaderGestureHandler(
                usePageTapZones: settings.usePageTapZones,
                isRTL: settings.mode.isRTL,
                isContinuousMode: settings.mode.isContinuous,
                navigationLayout: settings.navigationLayout,
                tappingInversion: settings.tappingInversion,
                onToggleUI: _toggleControls,
                onPreviousPage: _previousPage,
                onNextPage: _nextPage,
              ),
            ),
            _appBar(background),
            _bottomBar(background),
            ValueListenableBuilder<int>(
              valueListenable: _currentPage,
              builder: (_, index, _) => AnimatedOpacity(
                opacity: !_controlsVisible && settings.showPageNumbers ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_pageLabel(index)} / ${widget.pages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          shadows: [Shadow(blurRadius: 3)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gallery(Color background) {
    final child = settings.mode.isContinuous
        ? _continuousGallery()
        : _pagedGallery();
    return ColoredBox(
      color: background,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_colorMatrix()),
        child: child,
      ),
    );
  }

  Widget _pagedGallery() => PageView.builder(
    controller: _pageController,
    scrollDirection: settings.mode == ReaderMode.vertical
        ? Axis.vertical
        : Axis.horizontal,
    reverse: settings.mode == ReaderMode.rtl,
    itemCount: _displayCount,
    onPageChanged: (page) {
      final index = (page * _pageStep).clamp(0, widget.pages.length - 1);
      final trailing = _trailingIndex(index);
      _pagedIndex = index;
      _currentPage.value = trailing;
      _report(trailing);
    },
    itemBuilder: (_, pageIndex) {
      final index = pageIndex * _pageStep;
      if (_pageStep == 1 || index + 1 >= widget.pages.length) {
        return _photoPage(index);
      }
      final indices = settings.mode.isRTL ^ settings.dualPageInvert
          ? [index + 1, index]
          : [index, index + 1];
      return PhotoView.customChild(
        backgroundDecoration: BoxDecoration(
          color: settings.background.resolve(context),
        ),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 5,
        child: Row(
          children: [
            for (final item in indices)
              Expanded(child: _pageImage(widget.pages[item])),
          ],
        ),
      );
    },
  );

  Widget _photoPage(int index) => PhotoView.customChild(
    backgroundDecoration: BoxDecoration(
      color: settings.background.resolve(context),
    ),
    minScale: _photoScale(),
    maxScale: PhotoViewComputedScale.covered * 8,
    child: _pageImage(widget.pages[index]),
  );

  dynamic _photoScale() => switch (settings.scaleType) {
    ReaderScaleType.fitWidth => PhotoViewComputedScale.covered,
    ReaderScaleType.originalSize => 1.0,
    _ => PhotoViewComputedScale.contained,
  };

  Widget _continuousGallery() {
    final horizontal = settings.mode.isHorizontalContinuous;
    final padding =
        MediaQuery.sizeOf(context).width * settings.sidePadding / 100;
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _positions,
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      reverse: settings.mode == ReaderMode.horizontalContinuousRTL,
      itemCount: _displayCount + 1,
      itemBuilder: (_, index) {
        if (index == _displayCount) return _chapterTransition(horizontal);
        final leading = index * _pageStep;
        final pageIndices = _pageStep == 2 && leading + 1 < widget.pages.length
            ? settings.mode.isRTL ^ settings.dualPageInvert
                  ? [leading + 1, leading]
                  : [leading, leading + 1]
            : [leading];
        final page = Padding(
          padding: horizontal
              ? EdgeInsets.symmetric(vertical: settings.showPageGaps ? 3 : 0)
              : EdgeInsets.fromLTRB(
                  padding,
                  settings.showPageGaps && settings.mode != ReaderMode.webtoon
                      ? 3
                      : 0,
                  padding,
                  settings.showPageGaps && settings.mode != ReaderMode.webtoon
                      ? 3
                      : 0,
                ),
          child: pageIndices.length == 1
              ? _pageImage(widget.pages[leading])
              : Row(
                  children: [
                    for (final pageIndex in pageIndices)
                      Expanded(child: _pageImage(widget.pages[pageIndex])),
                  ],
                ),
        );
        if (!horizontal) return page;
        return SizedBox(
          width: MediaQuery.sizeOf(context).width,
          height: double.infinity,
          child: InteractiveViewer(
            minScale: settings.disableZoomOut ? 1 : .5,
            maxScale: 5,
            child: page,
          ),
        );
      },
    );
  }

  Widget _chapterTransition(bool horizontal) => SizedBox(
    width: horizontal ? MediaQuery.sizeOf(context).width : double.infinity,
    height: horizontal ? double.infinity : 260,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 48),
          const SizedBox(height: 12),
          const Text('Chapter completed'),
          const SizedBox(height: 8),
          if (widget.onNextChapter == null)
            const Text('There is no next chapter')
          else
            FilledButton.icon(
              onPressed: widget.onNextChapter,
              icon: const Icon(Icons.skip_next),
              label: const Text('Next chapter'),
            ),
        ],
      ),
    ),
  );

  Widget _pageImage(ReadPage page) {
    final uri = Uri.tryParse(page.url);
    final fit = settings.cropBorders ? BoxFit.cover : _boxFit();
    final child = uri?.scheme == 'file'
        ? Image.file(
            File.fromUri(uri!),
            fit: fit,
            width: double.infinity,
            errorBuilder: (_, _, _) => _imageError(),
          )
        : TerraNetworkImage(
            url: page.url,
            headers: page.headers,
            width: double.infinity,
            fit: fit,
            error: _imageError(),
          );
    return child;
  }

  BoxFit _boxFit() => switch (settings.scaleType) {
    ReaderScaleType.stretch => BoxFit.fill,
    ReaderScaleType.fitWidth => BoxFit.fitWidth,
    ReaderScaleType.fitHeight => BoxFit.fitHeight,
    ReaderScaleType.originalSize => BoxFit.none,
    ReaderScaleType.smartFit || ReaderScaleType.fitScreen => BoxFit.contain,
  };

  Widget _imageError() => const SizedBox(
    height: 260,
    child: Center(child: Icon(Icons.broken_image_outlined, size: 42)),
  );

  Widget _appBar(Color background) => AnimatedPositioned(
    duration: const Duration(milliseconds: 300),
    top: _controlsVisible ? 0 : -110,
    left: 0,
    right: 0,
    child: AppBar(
      backgroundColor: background.withValues(alpha: .94),
      foregroundColor: background.computeLuminance() > .5
          ? Colors.black
          : Colors.white,
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

  Widget _bottomBar(Color background) => AnimatedPositioned(
    duration: const Duration(milliseconds: 300),
    bottom: _controlsVisible ? 0 : -150,
    left: 0,
    right: 0,
    height: 140,
    child: Material(
      color: background.withValues(alpha: .96),
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
                    child: ValueListenableBuilder<int>(
                      valueListenable: _currentPage,
                      builder: (_, value, _) => Row(
                        children: [
                          SizedBox(
                            width: 38,
                            child: Text(
                              _pageLabel(value),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              padding: EdgeInsets.zero,
                              value: value.toDouble().clamp(
                                0,
                                max(0, widget.pages.length - 1).toDouble(),
                              ),
                              max: max(1, widget.pages.length - 1).toDouble(),
                              divisions: widget.pages.length > 1
                                  ? widget.pages.length - 1
                                  : null,
                              label: _pageLabel(value),
                              onChanged: (next) =>
                                  _setPage(next.round(), animate: false),
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              '${widget.pages.length}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
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
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  PopupMenuButton<ReaderMode>(
                    tooltip: 'Reading mode',
                    initialValue: settings.mode,
                    onSelected: (mode) {
                      setState(() => settings.mode = mode);
                      unawaited(settings.save());
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _setPage(_currentPage.value, animate: false);
                        _syncAutoScroll();
                      });
                    },
                    itemBuilder: (_) => [
                      for (final mode in ReaderMode.values)
                        PopupMenuItem(
                          value: mode,
                          child: Row(
                            children: [
                              Icon(settings.mode == mode ? Icons.check : null),
                              const SizedBox(width: 8),
                              Text(mode.label),
                            ],
                          ),
                        ),
                    ],
                    icon: const Icon(Icons.app_settings_alt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Crop borders',
                    onPressed: () {
                      setState(
                        () => settings.cropBorders = !settings.cropBorders,
                      );
                      unawaited(settings.save());
                    },
                    icon: Icon(
                      settings.cropBorders ? Icons.crop : Icons.crop_free,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Single or double page',
                    onPressed: settings.mode.isHorizontalContinuous
                        ? null
                        : () {
                            setState(() {
                              settings.pageMode =
                                  settings.pageMode == PageMode.onePage
                                  ? PageMode.doublePage
                                  : PageMode.onePage;
                            });
                            unawaited(settings.save());
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _setPage(_currentPage.value, animate: false);
                              }
                            });
                          },
                    icon: Icon(
                      settings.pageMode == PageMode.doublePage
                          ? Icons.menu_book
                          : Icons.book_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reader settings',
                    onPressed: () => showMangayomiMangaSettings(
                      context: context,
                      settings: settings,
                      onChanged: () {
                        if (!mounted) return;
                        setState(() {});
                        _applyWakeLock();
                        _syncAutoScroll();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _setPage(_currentPage.value, animate: false);
                          }
                        });
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

  String _pageLabel(int trailing) {
    final leading = _leadingIndex(trailing);
    return leading == trailing
        ? '${trailing + 1}'
        : '${leading + 1}-${trailing + 1}';
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
    } on PlatformException {
      // The runner may not register the wake-lock plugin in tests.
    }
  }

  List<double> _colorMatrix() {
    final brightness = settings.brightness * 255;
    final saturation = settings.grayscale ? 0.0 : settings.saturation;
    final inverse = settings.invertColors ? -1.0 : 1.0;
    final offset = settings.invertColors ? 255.0 : 0.0;
    final sr = (1 - saturation) * .2126;
    final sg = (1 - saturation) * .7152;
    final sb = (1 - saturation) * .0722;
    final contrast = settings.contrast * inverse;
    return [
      (sr + saturation) * contrast,
      sg * contrast,
      sb * contrast,
      0,
      offset + brightness,
      sr * contrast,
      (sg + saturation) * contrast,
      sb * contrast,
      0,
      offset + brightness,
      sr * contrast,
      sg * contrast,
      (sb + saturation) * contrast,
      0,
      offset + brightness,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
