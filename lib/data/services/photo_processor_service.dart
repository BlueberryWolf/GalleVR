import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/image/image_dimensions_reader.dart';
import '../../core/webp/webp_encoder_service.dart';
import '../models/config_model.dart';
import '../models/log_metadata.dart';
import '../models/photo_metadata.dart';
import '../repositories/photo_metadata_repository.dart';
import 'photo_event_service.dart';
import 'photo_upload_service.dart';
import 'vrchat_service.dart';
import 'vrcx_metadata_service.dart';

class PhotoProcessorService {
  final PhotoUploadService _photoUploadService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final WebpEncoderService _webpEncoderService;
  final VRChatService _vrchatService;

  PhotoProcessorService({
    PhotoUploadService? photoUploadService,
    PhotoMetadataRepository? photoMetadataRepository,
    WebpEncoderService? webpEncoderService,
    VRChatService? vrchatService,
  }) : _photoUploadService = photoUploadService ?? PhotoUploadService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _webpEncoderService = webpEncoderService ?? WebpEncoderService(),
       _vrchatService = vrchatService ?? VRChatService();

  Future<String?> processPhoto(
    String sourcePath,
    ConfigModel config,
    LogMetadata? metadata,
  ) async {
    final filename = path.basename(sourcePath);
    developer.log(
      'Starting to process photo: $filename',
      name: 'PhotoProcessorService',
    );
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        final error = 'Source file does not exist: $sourcePath';
        developer.log(error, name: 'PhotoProcessorService');
        PhotoEventService().notifyError('processing', error);
        return null;
      }

      final authData = await _vrchatService.loadAuthData();
      final secondaryAuth = await _vrchatService.loadAuthDataSecondary();

      final parsedMetadata = await VrcxMetadataService().extractVrcxMetadata(
        sourcePath,
      );
      final bool isResonite =
          (parsedMetadata?.application == 'Resonite') ||
          (config.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(config.resonitePhotosDirectory, sourcePath));

      final uploadAuth =
          isResonite
              ? (authData?.userId.startsWith('U-') == true
                  ? authData
                  : secondaryAuth)
              : (authData?.userId.startsWith('U-') == false
                  ? authData
                  : secondaryAuth);

      final badges =
          uploadAuth?.badges.map((b) => b.toLowerCase()).toList() ?? [];

      final webpPath = await compressPhotoToWebP(
        sourcePath,
        badges,
        isResonite: isResonite,
      );

      if (webpPath == null) {
        return null;
      }

      final sourceStats = file.statSync();
      final creationTimeMs = sourceStats.modified.millisecondsSinceEpoch;

      final photoMetadata = PhotoMetadata(
        takenDate: creationTimeMs,
        filename: filename,
        views: 0,
        world: parsedMetadata?.world ?? metadata?.world,
        players: parsedMetadata?.players ?? metadata?.players ?? [],
        localPath: sourcePath,
        application: isResonite ? 'Resonite' : parsedMetadata?.application,
        takenGlobalPosition: parsedMetadata?.takenGlobalPosition,
        takenGlobalRotation: parsedMetadata?.takenGlobalRotation,
        takenGlobalScale: parsedMetadata?.takenGlobalScale,
        cameraFov: parsedMetadata?.cameraFov,
        cameraManufacturer: parsedMetadata?.cameraManufacturer,
        takenById: parsedMetadata?.takenById,
        isNonVrcx:
            isResonite
                ? false
                : (parsedMetadata?.isNonVrcx ??
                    (parsedMetadata?.world == null && metadata?.world == null)),
      );

      final saveResult = await _photoMetadataRepository.savePhotoMetadata(
        photoMetadata,
      );
      developer.log(
        'Metadata saved: $saveResult for ${photoMetadata.filename}',
        name: 'PhotoProcessorService',
      );

      String metadataDetails = 'Metadata saved locally';
      if (photoMetadata.world != null) {
        metadataDetails +=
            ' (World: ${photoMetadata.world!.name}, Players: ${photoMetadata.players.length})';
      }
      PhotoEventService().notifyError(
        'info',
        metadataDetails,
        photoPath: sourcePath,
      );

      if (config.uploadEnabled) {
        developer.log(
          'Starting asynchronous upload for photo: ${path.basename(webpPath)}',
          name: 'PhotoProcessorService',
        );
        PhotoEventService().notifyError(
          'info',
          'Starting upload process...',
          photoPath: sourcePath,
        );

        _photoUploadService
            .uploadPhoto(
              webpPath,
              config,
              metadata,
              metadata: photoMetadata,
              originalPath: sourcePath,
              deleteFileOnComplete: true,
            )
            .then((uploadSuccess) async {
              if (uploadSuccess) {
                developer.log(
                  'Background photo upload completed successfully',
                  name: 'PhotoProcessorService',
                );

                final updatedMetadata = await _photoMetadataRepository
                    .getPhotoMetadataForFile(sourcePath);
                if (updatedMetadata != null &&
                    updatedMetadata.galleryUrl != null) {
                  developer.log(
                    'Photo has gallery URL: ${updatedMetadata.galleryUrl}',
                    name: 'PhotoProcessorService',
                  );
                } else {
                  developer.log(
                    'No gallery URL found after background upload',
                    name: 'PhotoProcessorService',
                  );
                  PhotoEventService().notifyError(
                    'warning',
                    'Upload succeeded but no gallery URL was found',
                    photoPath: sourcePath,
                  );
                }
              } else {
                developer.log(
                  'Background photo upload failed',
                  name: 'PhotoProcessorService',
                );
              }
            })
            .catchError((e) {
              developer.log(
                'Unhandled error in background photo upload: $e',
                name: 'PhotoProcessorService',
              );
            });
      } else {
        PhotoEventService().notifyError(
          'success',
          'Photo processing completed successfully',
          photoPath: sourcePath,
        );

        try {
          final webpFile = File(webpPath);
          if (await webpFile.exists()) {
            await webpFile.delete();
            developer.log(
              'Deleted temporary WebP file: $webpPath',
              name: 'PhotoProcessorService',
            );
          }
        } catch (e) {
          developer.log(
            'Error deleting temporary WebP file: $e',
            name: 'PhotoProcessorService',
          );
        }
      }

      return sourcePath;
    } catch (e) {
      final error = 'Unexpected error processing photo: $e';
      developer.log(error, name: 'PhotoProcessorService');
      PhotoEventService().notifyError(
        'processing',
        error,
        photoPath: sourcePath,
      );
      return null;
    }
  }

  Future<String?> compressPhotoToWebP(
    String sourcePath,
    List<String> badges, {
    required bool isResonite,
  }) async {
    final filename = path.basename(sourcePath);
    try {
      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory(
        path.join(
          tempDir.path,
          'GalleVR-Temp',
          DateTime.now().toIso8601String().split('T')[0],
        ),
      );

      if (!await outputDir.exists()) {
        developer.log(
          'Creating output directory: ${outputDir.path}',
          name: 'PhotoProcessorService',
        );
        await outputDir.create(recursive: true);
      }

      final fileName = path.basenameWithoutExtension(sourcePath);
      final outputPath = path.join(outputDir.path, '$fileName.webp');

      final tier = _getTierSettings(badges);
      final int maxDimension = tier['maxDimension']!;
      final int webpQuality = tier['webpQuality']!;
      final int maxSizeBytes = tier['maxSizeBytes']!;

      int width = 0;
      int height = 0;

      try {
        final dims = await ImageDimensionsReader.readFromFile(sourcePath);
        if (dims != null) {
          width = dims.width;
          height = dims.height;
        }
      } catch (e) {
        developer.log(
          'Failed to parse image dimensions: $e',
          name: 'PhotoProcessorService',
        );
      }

      if (width <= 0 || height <= 0) {
        final error =
            'Failed to determine image dimensions from header: $filename';
        developer.log(error, name: 'PhotoProcessorService');
        PhotoEventService().notifyError(
          'processing',
          error,
          photoPath: sourcePath,
        );
        return null;
      }

      if (!isResonite && !_isValidAspectRatio(width, height)) {
        final ratio = (width / height).toStringAsFixed(2);
        final error = 'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
        developer.log(error, name: 'PhotoProcessorService');
        PhotoEventService().notifyError(
          'processing',
          error,
          photoPath: sourcePath,
        );
        return null;
      }

      int? targetWidth;
      int? targetHeight;

      if (width > maxDimension || height > maxDimension) {
        if (width > height) {
          targetWidth = maxDimension;
          targetHeight = (height * (maxDimension / width)).round();
        } else {
          targetHeight = maxDimension;
          targetWidth = (width * (maxDimension / height)).round();
        }
      }

      final int processedWidth = targetWidth ?? width;
      final int processedHeight = targetHeight ?? height;
      final int processedPixels = processedWidth * processedHeight;
      final int maxTierPixels = tier['maxTierPixels']!;

      int scaledMaxSizeBytes =
          (maxSizeBytes * (processedPixels / maxTierPixels)).round();
      scaledMaxSizeBytes = scaledMaxSizeBytes.clamp(153600, maxSizeBytes);
      if (scaledMaxSizeBytes > maxSizeBytes) {
        scaledMaxSizeBytes = maxSizeBytes;
      }

      developer.log(
        'Dynamic size ceiling: $scaledMaxSizeBytes bytes for resolution ${processedWidth}x$processedHeight (max tier limit: $maxSizeBytes bytes)',
        name: 'PhotoProcessorService',
      );

      if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
        developer.log(
          'Using fast-path direct cwebp/native encoding on $sourcePath',
          name: 'PhotoProcessorService',
        );
        await _webpEncoderService.encodeFileToWebP(
          sourcePath,
          outputPath,
          quality: webpQuality,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          maxSizeBytes: scaledMaxSizeBytes,
          originalWidth: width,
          originalHeight: height,
        );

        developer.log(
          'Direct cwebp/native encoding completed successfully: $outputPath',
          name: 'PhotoProcessorService',
        );
      } else {
        developer.log(
          'Unsupported platform for WebP encoding: ${Platform.operatingSystem}',
          name: 'PhotoProcessorService',
        );
        return null;
      }

      return outputPath;
    } catch (e) {
      developer.log(
        'Error in compressPhotoToWebP: $e',
        name: 'PhotoProcessorService',
      );
      PhotoEventService().notifyError(
        'processing',
        'Error compressing photo: $e',
        photoPath: sourcePath,
      );
      return null;
    }
  }

  bool _isValidAspectRatio(int width, int height) {
    const tolerance = 0.01;
    final ratio = width / height;
    final ratio16_9 = 16.0 / 9.0;
    final ratio9_16 = 9.0 / 16.0;

    return (ratio - ratio16_9).abs() < tolerance ||
        (ratio - ratio9_16).abs() < tolerance;
  }

  Map<String, dynamic> _getTierSettings(List<String> badges) {
    if (badges.contains('mega_supporter') ||
        badges.contains('mega supporter')) {
      return {
        'maxDimension': 7680, // 8K
        'webpQuality': 95,
        'maxSizeBytes': 5242880, // 5.0MB limit
        'maxTierPixels': 33177600, // 7680x4320
      };
    } else if (badges.contains('super_supporter') ||
        badges.contains('super supporter')) {
      return {
        'maxDimension': 3840, // 4K
        'webpQuality': 92,
        'maxSizeBytes': 2621440, // 2.5MB limit
        'maxTierPixels': 8294400, // 3840x2160
      };
    } else if (badges.contains('supporter')) {
      return {
        'maxDimension': 2560, // 2K
        'webpQuality': 90,
        'maxSizeBytes': 1048576, // 1MB limit
        'maxTierPixels': 3686400, // 2560x1440
      };
    } else {
      return {
        'maxDimension': 1920, // 1080p
        'webpQuality': 85,
        'maxSizeBytes': 153600, // 150KB limit
        'maxTierPixels': 2073600, // 1920x1080
      };
    }
  }
}
