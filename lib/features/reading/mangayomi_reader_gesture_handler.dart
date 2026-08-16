// Ported from Mangayomi, Apache-2.0.
// https://github.com/kodjodevf/mangayomi/blob/main/lib/modules/manga/reader/widgets/reader_gesture_handler.dart

import 'package:flutter/material.dart';

class MangayomiReaderGestureHandler extends StatelessWidget {
  const MangayomiReaderGestureHandler({
    super.key,
    required this.usePageTapZones,
    required this.isRTL,
    required this.isContinuousMode,
    required this.navigationLayout,
    required this.tappingInversion,
    required this.onToggleUI,
    required this.onPreviousPage,
    required this.onNextPage,
    this.onDoubleTapDown,
    this.onDoubleTap,
  });

  final bool usePageTapZones;
  final bool isRTL;
  final bool isContinuousMode;
  final int navigationLayout;
  final int tappingInversion;
  final VoidCallback onToggleUI;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<Offset>? onDoubleTapDown;
  final VoidCallback? onDoubleTap;

  bool get _invertHorizontal => tappingInversion == 1 || tappingInversion == 3;
  bool get _invertVertical => tappingInversion == 2 || tappingInversion == 3;
  VoidCallback get _previous => isRTL ? onNextPage : onPreviousPage;
  VoidCallback get _next => isRTL ? onPreviousPage : onNextPage;

  _ReaderZone _zone(VoidCallback action) => _ReaderZone(
    onTap: usePageTapZones ? action : onToggleUI,
    onDoubleTapDown: isContinuousMode ? onDoubleTapDown : null,
    onDoubleTap: isContinuousMode ? onDoubleTap : null,
  );

  _ReaderZone _ui() => _ReaderZone(
    onTap: onToggleUI,
    onDoubleTapDown: isContinuousMode ? onDoubleTapDown : null,
    onDoubleTap: isContinuousMode ? onDoubleTap : null,
  );

  @override
  Widget build(BuildContext context) => switch (navigationLayout) {
    1 => _lShaped(),
    2 => _kindle(),
    3 => _edge(),
    4 => _rightAndLeft(),
    5 => SizedBox.expand(child: _ui()),
    _ => _default(),
  };

  Widget _default() {
    final left = _invertHorizontal ? _next : _previous;
    final right = _invertHorizontal ? _previous : _next;
    final top = _invertVertical ? onNextPage : onPreviousPage;
    final bottom = _invertVertical ? onPreviousPage : onNextPage;
    return Stack(
      children: [
        Row(
          children: [
            Expanded(flex: 2, child: _zone(left)),
            Expanded(flex: 2, child: _ui()),
            Expanded(flex: 2, child: _zone(right)),
          ],
        ),
        Column(
          children: [
            Expanded(flex: 2, child: _zone(top)),
            const Expanded(flex: 5, child: SizedBox.shrink()),
            Expanded(flex: 2, child: _zone(bottom)),
          ],
        ),
      ],
    );
  }

  Widget _lShaped() {
    final invert = _invertHorizontal ^ _invertVertical;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _zone(invert ? _next : _previous)),
              Expanded(flex: 2, child: _ui()),
            ],
          ),
        ),
        Expanded(flex: 2, child: _ui()),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 2, child: _ui()),
              Expanded(child: _zone(invert ? _previous : _next)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kindle() {
    final left = _invertHorizontal ? _next : _previous;
    final right = _invertHorizontal ? _previous : _next;
    return Column(
      children: [
        Expanded(child: _ui()),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(child: _zone(left)),
              Expanded(child: _zone(right)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _edge() {
    final left = _invertHorizontal ? _next : _previous;
    final right = _invertHorizontal ? _previous : _next;
    return Row(
      children: [
        Expanded(child: _zone(left)),
        Expanded(flex: 5, child: _ui()),
        Expanded(child: _zone(right)),
      ],
    );
  }

  Widget _rightAndLeft() {
    final left = _invertHorizontal ? _next : _previous;
    final right = _invertHorizontal ? _previous : _next;
    return Row(
      children: [
        Expanded(child: _zone(left)),
        Expanded(child: _zone(right)),
      ],
    );
  }
}

class _ReaderZone extends StatelessWidget {
  const _ReaderZone({
    required this.onTap,
    this.onDoubleTapDown,
    this.onDoubleTap,
  });

  final VoidCallback onTap;
  final ValueChanged<Offset>? onDoubleTapDown;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: onTap,
    onDoubleTapDown: onDoubleTapDown == null
        ? null
        : (details) => onDoubleTapDown!(details.globalPosition),
    onDoubleTap: onDoubleTap,
  );
}
