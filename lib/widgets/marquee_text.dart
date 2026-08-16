import 'package:flutter/material.dart';

class MarqueeText extends StatelessWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.gap = 32,
    this.velocity = 30,
  });

  final String text;
  final TextStyle? style;
  final double gap;
  final double velocity;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final direction = Directionality.of(context);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (!constraints.hasBoundedWidth ||
          painter.width <= constraints.maxWidth) {
        return Text(text, maxLines: 1, style: style);
      }
      return _MarqueeTrack(
        text: text,
        style: style,
        width: painter.width,
        height: painter.height,
        gap: gap,
        velocity: velocity,
      );
    },
  );
}

class _MarqueeTrack extends StatefulWidget {
  const _MarqueeTrack({
    required this.text,
    required this.style,
    required this.width,
    required this.height,
    required this.gap,
    required this.velocity,
  });

  final String text;
  final TextStyle? style;
  final double width;
  final double height;
  final double gap;
  final double velocity;

  @override
  State<_MarqueeTrack> createState() => _MarqueeTrackState();
}

class _MarqueeTrackState extends State<_MarqueeTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..duration = _duration
      ..repeat();
  }

  Duration get _duration => Duration(
    milliseconds: ((widget.width + widget.gap) / widget.velocity * 1000)
        .round(),
  );

  @override
  void didUpdateWidget(covariant _MarqueeTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width ||
        oldWidget.gap != widget.gap ||
        oldWidget.velocity != widget.velocity) {
      _controller
        ..duration = _duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    child: ExcludeSemantics(
      child: ClipRect(
        child: SizedBox(
          height: widget.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                -_controller.value * (widget.width + widget.gap),
                0,
              ),
              child: child,
            ),
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, maxLines: 1, style: widget.style),
                  SizedBox(width: widget.gap),
                  Text(widget.text, maxLines: 1, style: widget.style),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
