import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final terraImageCache = CacheManager(
  Config(
    'terra_images_v1',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 500,
  ),
);

class TerraNetworkImage extends StatelessWidget {
  const TerraNetworkImage({
    super.key,
    required this.url,
    required this.error,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.headers,
  });

  final String url;
  final Widget error;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: url,
    cacheManager: terraImageCache,
    width: width,
    height: height,
    fit: fit,
    httpHeaders: headers,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    placeholder: (_, _) => error,
    errorWidget: (_, _, _) => error,
  );
}
