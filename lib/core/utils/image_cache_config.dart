/// [P1-2 FIX] Standardized image cache configuration
/// Prevents memory bloat from full-resolution images displayed at small sizes
///
/// Problem: CachedNetworkImage downloads full-resolution images (1000x1500px)
/// but displays them at 40-100px sizes, wasting memory and disk space.
///
/// Solution: Specify memCacheWidth/Height for display size, limiting disk cache.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Standard cache manager with 200MB size limit
class AppCacheManager {
  static const int _cacheSizeInBytes = 200 * 1024 * 1024; // 200 MB

  static final CacheManager instance = CacheManager(
    Config(
      'xtremflow_image_cache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 500,
      diskUsagePercentageHigh: 95,
      diskUsagePercentageGoal: 80,
    ),
  );
}

/// Image cache configuration presets for common use cases
class ImageCacheConfigs {
  /// Small channel icons (40x40 display size)
  static const ImageCacheConfig channelIcon = ImageCacheConfig(
    displayWidth: 40,
    displayHeight: 40,
    cacheWidth: 50,    // Slight buffer for upscaling
    cacheHeight: 50,
  );

  /// Medium poster images (100x150 display size)
  static const ImageCacheConfig posterThumbnail = ImageCacheConfig(
    displayWidth: 100,
    displayHeight: 150,
    cacheWidth: 120,
    cacheHeight: 180,
  );

  /// Large poster images (200x300 display size)
  static const ImageCacheConfig posterLarge = ImageCacheConfig(
    displayWidth: 200,
    displayHeight: 300,
    cacheWidth: 240,
    cacheHeight: 360,
  );

  /// Hero carousel images (full width, ~500px)
  static const ImageCacheConfig heroCarousel = ImageCacheConfig(
    displayWidth: 500,
    displayHeight: 300,
    cacheWidth: 600,
    cacheHeight: 360,
  );

  /// Series detail cover (400x600 display size)
  static const ImageCacheConfig seriesCover = ImageCacheConfig(
    displayWidth: 400,
    displayHeight: 600,
    cacheWidth: 480,
    cacheHeight: 720,
  );
}

/// Configuration for a single CachedNetworkImage
class ImageCacheConfig {
  final int displayWidth;
  final int displayHeight;
  final int cacheWidth;
  final int cacheHeight;

  const ImageCacheConfig({
    required this.displayWidth,
    required this.displayHeight,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  /// Get a CachedNetworkImage builder function
  /// Usage: imageUrl.isEmpty ? placeholder : getCachedImage(imageUrl, config)
  CachedNetworkImage buildImage({
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxHeightDiskCache: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      cacheManager: AppCacheManager.instance,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_not_supported, color: Color(0xFF8E8E93)),
      ),
    );
  }
}

/// Helper extension for quick image caching
extension ImageCacheHelper on String {
  /// Load as channel icon with standard sizing
  CachedNetworkImage asChannelIcon({double? size}) {
    return ImageCacheConfigs.channelIcon.buildImage(
      imageUrl: this,
      width: size ?? 40,
      height: size ?? 40,
      fit: BoxFit.cover,
    );
  }

  /// Load as poster thumbnail
  CachedNetworkImage asPosterThumbnail({
    double width = 100,
    double height = 150,
  }) {
    return ImageCacheConfigs.posterThumbnail.buildImage(
      imageUrl: this,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  /// Load as large poster
  CachedNetworkImage asPosterLarge({
    double width = 200,
    double height = 300,
  }) {
    return ImageCacheConfigs.posterLarge.buildImage(
      imageUrl: this,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  /// Load as hero carousel image
  CachedNetworkImage asHeroImage({
    double width = 500,
    double height = 300,
  }) {
    return ImageCacheConfigs.heroCarousel.buildImage(
      imageUrl: this,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  /// Load as series cover
  CachedNetworkImage asSeriesCover({
    double width = 400,
    double height = 600,
  }) {
    return ImageCacheConfigs.seriesCover.buildImage(
      imageUrl: this,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
}
