// Adapted from Mangayomi's aniskip_countdown_btn.dart.
// Source: https://github.com/kodjodevf/mangayomi (Apache-2.0), modified.
// ignore_for_file: curly_braces_in_flow_control_structures, unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'player_source.dart';

class AniSkipCountdownButton extends StatefulWidget {
  const AniSkipCountdownButton({
    super.key,
    required this.segment,
    required this.player,
    required this.autoSkip,
    this.timeout = const Duration(seconds: 5),
  });
  final PlayerSkipSegment segment;
  final Player player;
  final bool autoSkip;
  final Duration timeout;
  @override
  State<AniSkipCountdownButton> createState() => _AniSkipCountdownButtonState();
}

class _AniSkipCountdownButtonState extends State<AniSkipCountdownButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: widget.timeout,
  )..forward();
  bool completed = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoSkip) {
      WidgetsBinding.instance.addPostFrameCallback((_) => skip());
    } else {
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted)
          setState(() => completed = true);
      });
    }
  }

  void skip() {
    widget.player.seek(widget.segment.end);
    if (mounted) setState(() => completed = true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => completed
      ? const SizedBox.shrink()
      : AnimatedBuilder(
          animation: controller,
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: MaterialButton(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              onPressed: skip,
              child: Container(
                width: 200,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LinearProgressIndicator(
                        value: 1 - controller.value,
                        color: Colors.red,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              widget.segment.label.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${widget.timeout.inSeconds - (widget.timeout * controller.value).inSeconds}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
