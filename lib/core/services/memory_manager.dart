import 'dart:developer' as developer;
import 'package:flutter/painting.dart';

import '../image/image_cache_service.dart';
import '../image/thumbnail_provider.dart';
import '../isolate/isolate_worker_pool.dart';
import '../../data/database/app_database.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/vrcx_metadata_service.dart';
import '../../presentation/widgets/cached_image.dart';

class MemoryManager {
  MemoryManager._();

  static Future<void> purgeUiResources() async {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.maximumSize = 0;
      imageCache.maximumSizeBytes = 0;
      imageCache.clear();
      imageCache.clearLiveImages();
      PaintingBinding.instance.handleMemoryPressure();
    } catch (e) {
      developer.log('Error purging image cache: $e', name: 'MemoryManager');
    }

    try {
      CachedImage.clearAllProviders();
      ThumbnailProvider().clearThumbnails();
    } catch (e) {
      developer.log(
        'Error clearing CachedImage providers: $e',
        name: 'MemoryManager',
      );
    }

    try {
      VrcxMetadataService().clearCache();
    } catch (e) {
      developer.log(
        'Error clearing VRCX metadata cache: $e',
        name: 'MemoryManager',
      );
    }

    try {
      IsolateWorkerPool().trimIdleWorkers();
    } catch (e) {
      developer.log(
        'Error trimming idle isolate workers: $e',
        name: 'MemoryManager',
      );
    }

    try {
      await AppServiceManager().soundService.releasePlayer();
    } catch (e) {
      developer.log(
        'Error releasing idle audio player: $e',
        name: 'MemoryManager',
      );
    }

    try {
      await AppDatabase().shrinkMemory();
    } catch (e) {
      developer.log(
        'Error shrinking SQLite memory: $e',
        name: 'MemoryManager',
      );
    }
  }

  static void restoreUiResources() {
    ImageCacheService.applyMemoryLimits();
  }
}
