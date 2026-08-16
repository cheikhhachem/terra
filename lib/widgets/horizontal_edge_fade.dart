import 'package:flutter/material.dart';

class HorizontalEdgeFade extends StatefulWidget {
  const HorizontalEdgeFade({super.key, required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<HorizontalEdgeFade> createState() => _HorizontalEdgeFadeState();
}

class _HorizontalEdgeFadeState extends State<HorizontalEdgeFade> {
  final _controller = ScrollController();
  bool _showStart = false;
  bool _showEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void didUpdateWidget(covariant HorizontalEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  void _updateFades() {
    if (!mounted || !_controller.hasClients) return;
    final showStart = _controller.position.extentBefore > 0;
    final showEnd = _controller.position.extentAfter > 0;
    if (showStart == _showStart && showEnd == _showEnd) return;
    setState(() {
      _showStart = showStart;
      _showEnd = showEnd;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final edge = (28 / bounds.width).clamp(0.0, .5);
        return LinearGradient(
          colors: [
            _showStart ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            _showEnd ? Colors.transparent : Colors.white,
          ],
          stops: [0, edge, 1 - edge, 1],
        ).createShader(bounds);
      },
      child: widget.builder(_controller),
    );
  }
}
