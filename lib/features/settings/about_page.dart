import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../widgets/terra_brand.dart';
import '../../widgets/terra_header.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const TerraHeader(title: Text('About'), nested: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const TerraBrandHero(large: true),
                const SizedBox(height: 4),
                Text(
                  'Your media, your sources.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                _Fact(label: 'Developer', value: 'Cheik Hachem'),
                FutureBuilder(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => _Fact(
                    label: 'Version',
                    value: snapshot.hasData
                        ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                        : 'Loading...',
                  ),
                ),
                const _Fact(label: 'License', value: 'GPL-3.0-or-later'),
                const SizedBox(height: 20),
                Text(
                  'Terra is a media library and player for your own sources.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: Text(value, style: Theme.of(context).textTheme.bodySmall),
  );
}
