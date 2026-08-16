import 'package:flutter/material.dart';

import 'terra_network_image.dart';

class SourceIcon extends StatelessWidget {
  const SourceIcon({super.key, required this.url, this.size = 40});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 4),
    child: SizedBox.square(
      dimension: size,
      child: url.isEmpty
          ? const ColoredBox(
              color: Color(0x1FFFFFFF),
              child: Icon(Icons.extension_outlined),
            )
          : TerraNetworkImage(
              url: url,
              fit: BoxFit.cover,
              error: const ColoredBox(
                color: Color(0x1FFFFFFF),
                child: Icon(Icons.extension_outlined),
              ),
            ),
    ),
  );
}
