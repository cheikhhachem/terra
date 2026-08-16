import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _GlobalTickerProvider implements TickerProvider {
  const _GlobalTickerProvider();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

class TerraBrand extends StatefulWidget {
  const TerraBrand({super.key, this.large = false});
  final bool large;

  @override
  State<TerraBrand> createState() => _TerraBrandState();
}

class _TerraBrandState extends State<TerraBrand> {
  static const _tickerProvider = _GlobalTickerProvider();
  static AnimationController? _sphereController;
  static AnimationController? _continentsController;
  static AnimationController? _logoController;

  static bool _showingNatural = false;
  static bool _finishing = false;
  static int _instanceCount = 0;

  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _instanceCount++;
    _sphereController ??= AnimationController(
      vsync: _tickerProvider,
      duration: const Duration(seconds: 20),
    )..repeat();
    _continentsController ??= AnimationController(
      vsync: _tickerProvider,
      duration: const Duration(seconds: 30),
    )..repeat();
    _logoController ??= AnimationController(
      vsync: _tickerProvider,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _instanceCount--;
    if (_instanceCount <= 0) {
      _instanceCount = 0;
      _sphereController?.dispose();
      _continentsController?.dispose();
      _logoController?.dispose();
      _sphereController = null;
      _continentsController = null;
      _logoController = null;
    }
    super.dispose();
  }

  Future<void> _onLogoTap() async {
    if (_finishing) return;

    _tapCount++;

    if (_tapCount >= 3) {
      _tapCount = 0;

      if (_showingNatural) {
        _showingNatural = false;
        _sphereController!.repeat();
        _continentsController!.repeat();
        _logoController!.repeat(reverse: true);
        if (mounted) setState(() {});
        return;
      }

      _finishing = true;

      await Future.wait([
        _sphereController!.animateTo(
          1.0,
          duration: const Duration(seconds: 2),
        ),
        _continentsController!.animateTo(
          1.0,
          duration: const Duration(seconds: 2),
        ),
        _logoController!.animateTo(
          1.0,
          duration: const Duration(seconds: 2),
        ),
      ]);

      _finishing = false;
      _showingNatural = true;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.large ? 160.0 : 108.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.large ? 28 : 20),
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              onTap: _onLogoTap,
              behavior: HitTestBehavior.opaque,
              child: _showingNatural
                  ? SvgPicture.asset(
                      'assets/svg/icon_natural.svg',
                      width: size,
                      height: size,
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        RotationTransition(
                          turns: _sphereController!,
                          child: SvgPicture.asset(
                            'assets/svg/icon_sphere.svg',
                            width: size,
                            height: size,
                          ),
                        ),
                        RotationTransition(
                          turns: ReverseAnimation(_continentsController!),
                          child: SvgPicture.asset(
                            'assets/svg/icon_continents.svg',
                            width: size,
                            height: size,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _logoController!,
                          builder: (context, child) {
                            final t = _logoController!.value;
                            final y = -10.0 * math.sin(t * math.pi);
                            final x = 1.0 * math.cos(t * math.pi);
                            return Transform.translate(
                              offset: Offset(x, y),
                              child: child,
                            );
                          },
                          child: SvgPicture.asset(
                            'assets/svg/icon_logo.svg',
                            width: size,
                            height: size,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Terra',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: widget.large ? 44 : 28,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class TerraBrandHero extends StatelessWidget {
  const TerraBrandHero({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'terra-brand',
    flightShuttleBuilder: (_, _, _, _, to) =>
        FittedBox(fit: BoxFit.scaleDown, child: to.widget),
    child: Material(
      color: Colors.transparent,
      child: TerraBrand(large: large),
    ),
  );
}
