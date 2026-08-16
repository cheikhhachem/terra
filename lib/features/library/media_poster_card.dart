import 'dart:io';

import 'package:flutter/material.dart';

import '../../widgets/terra_network_image.dart';

class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.subtitle,
    this.secondarySubtitle,
    this.action,
    this.progress,
  });

  final String title;
  final String imageUrl;
  final String? subtitle;
  final String? secondarySubtitle;
  final Widget? action;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Poster(url: imageUrl),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.05,
                colors: [Colors.transparent, Color(0x73000000)],
                stops: [.45, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Colors.transparent,
                  Color(0xE6000000),
                ],
                stops: [0, .48, 1],
              ),
            ),
          ),
          if (action != null) Positioned(top: 0, right: 0, child: action!),
          Positioned(
            left: 12,
            right: 12,
            bottom: progress == null ? 12 : 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
                if (subtitle?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
                if (secondarySubtitle?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondarySubtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 9),
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 9),
                  LinearProgressIndicator(
                    value: progress!.clamp(0, 1),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: Colors.white30,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => url.isEmpty
      ? ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.movie_outlined, size: 42)),
        )
      : _isLocal(url)
      ? Image.file(
          File(
            Uri.tryParse(url)?.scheme == 'file'
                ? Uri.parse(url).toFilePath()
                : url,
          ),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _error(context),
        )
      : TerraNetworkImage(
          url: url,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          error: _error(context),
        );

  bool _isLocal(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'file' || (uri?.scheme.isEmpty ?? true);
  }

  Widget _error(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image_outlined, size: 42)),
  );
}
