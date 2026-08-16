import 'package:flutter/material.dart';

class TerraBrand extends StatelessWidget {
  const TerraBrand({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(large ? 28 : 20),
        child: Image.asset(
          'assets/terra_icon.png',
          width: large ? 112 : 76,
          height: large ? 112 : 76,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Terra',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: large ? 44 : 28,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
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
