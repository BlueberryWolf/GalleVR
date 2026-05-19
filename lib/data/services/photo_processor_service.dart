import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/webp/webp_encoder_service.dart';
import '../models/config_model.dart';
import '../models/log_metadata.dart';
import '../models/photo_metadata.dart';
import '../repositories/photo_metadata_repository.dart';
import 'photo_event_service.dart';
import 'photo_upload_service.dart';
import 'vrchat_service.dart';

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

        try {
          final file = File(sourcePath);
          if (!await file.exists()) {
            final error = 'Source file does not exist: $sourcePath';
            developer.log(error, name: 'PhotoProcessorService');
            PhotoEventService().notifyError('processing', error);
            return null;
          }

          final authData = await _vrchatService.loadAuthData();
          final badges =
              authData?.badges.map((b) => b.toLowerCase()).toList() ?? [];

          final tier = _getTierSettings(badges);
          final int maxDimension = tier['maxDimension']!;
          final int webpQuality = tier['webpQuality']!;
          final int maxSizeBytes = tier['maxSizeBytes']!;

          if (Platform.isWindows || Platform.isLinux) {
            developer.log(
              'Using Windows/Linux fast-path direct cwebp encoding on $sourcePath',
              name: 'PhotoProcessorService',
            );
            int width = 0;
            int height = 0;

            try {
              final raf = await file.open(mode: FileMode.read);
              final headerBytes = await raf.read(24);
              await raf.close();

              if (headerBytes.length >= 24 &&
                  headerBytes[0] == 0x89 &&
                  headerBytes[1] == 0x50 &&
                  headerBytes[2] == 0x4E &&
                  headerBytes[3] == 0x47) {
                final bd = ByteData.sublistView(headerBytes);
                width = bd.getInt32(16, Endian.big);
                height = bd.getInt32(20, Endian.big);
              }
            } catch (e) {
              developer.log(
                'Failed to parse PNG header: $e',
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

            if (!_isValidAspectRatio(width, height)) {
              final ratio = (width / height).toStringAsFixed(2);
              final error =
                  'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
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

            await _webpEncoderService.encodeFileToWebP(
              sourcePath,
              outputPath,
              quality: webpQuality,
              targetWidth: targetWidth,
              targetHeight: targetHeight,
              maxSizeBytes: scaledMaxSizeBytes,
            );

            developer.log(
              'Direct cwebp encoding completed successfully: $outputPath',
              name: 'PhotoProcessorService',
            );
          } else {
            final bytes = await file.readAsBytes();
            final image = await _decodeImage(bytes);

            if (image == null) {
              final error = 'Failed to decode image: $filename';
              developer.log(error, name: 'PhotoProcessorService');
              PhotoEventService().notifyError(
                'processing',
                error,
                photoPath: sourcePath,
              );
              return null;
            }

            if (!_isValidAspectRatio(image.width, image.height)) {
              final ratio = (image.width / image.height).toStringAsFixed(2);
              final error =
                  'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
              developer.log(error, name: 'PhotoProcessorService');
              PhotoEventService().notifyError(
                'processing',
                error,
                photoPath: sourcePath,
              );
              return null;
            }

            final processedImage = await _resizeImageIfNeeded(
              image,
              maxDimension,
            );

            final int processedPixels =
                processedImage.width * processedImage.height;
            final int maxTierPixels = tier['maxTierPixels']!;

            int scaledMaxSizeBytes =
                (maxSizeBytes * (processedPixels / maxTierPixels)).round();
            scaledMaxSizeBytes = scaledMaxSizeBytes.clamp(153600, maxSizeBytes);
            if (scaledMaxSizeBytes > maxSizeBytes) {
              scaledMaxSizeBytes = maxSizeBytes;
            }

            developer.log(
              'Fallback path dynamic size ceiling: $scaledMaxSizeBytes bytes for resolution ${processedImage.width}x${processedImage.height} (max tier limit: $maxSizeBytes bytes)',
              name: 'PhotoProcessorService',
            );

            Uint8List webpBytes = await _encodeToWebP(
              processedImage,
              webpQuality,
            );

            if (webpBytes.length > scaledMaxSizeBytes) {
              int currentQuality = webpQuality;
              developer.log(
                'Initial encode too large for user tier (${webpBytes.length} bytes, limit is $scaledMaxSizeBytes), starting iterative compression...',
                name: 'PhotoProcessorService',
              );

              while (webpBytes.length > scaledMaxSizeBytes &&
                  currentQuality > 50) {
                currentQuality -= 10;
                if (currentQuality < 50) currentQuality = 50;
                webpBytes = await _encodeToWebP(processedImage, currentQuality);
                developer.log(
                  'Retry quality $currentQuality produced ${webpBytes.length} bytes',
                  name: 'PhotoProcessorService',
                );
                if (currentQuality <= 50) break;
              }
            }

            developer.log(
              'Final WebP: ${webpBytes.length} bytes (Quality: $webpQuality / Limit: $scaledMaxSizeBytes)',
              name: 'PhotoProcessorService',
            );

            await File(outputPath).writeAsBytes(webpBytes);
            developer.log(
              'Saved WebP file to: $outputPath',
              name: 'PhotoProcessorService',
            );
          }

          final sourceFile = File(sourcePath);
          final sourceStats = sourceFile.statSync();
          final creationTimeMs = sourceStats.modified.millisecondsSinceEpoch;

          final photoMetadata = PhotoMetadata(
            takenDate: creationTimeMs,
            filename: path.basename(sourcePath),
            views: 0,
            world: metadata?.world,
            players: metadata?.players ?? [],
            localPath: sourcePath,
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
              'Starting asynchronous upload for photo: ${path.basename(outputPath)}',
              name: 'PhotoProcessorService',
            );
            PhotoEventService().notifyError(
              'info',
              'Starting upload process...',
              photoPath: sourcePath,
            );

            _photoUploadService
                .uploadPhoto(
                  outputPath,
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
          }

          if (!config.uploadEnabled) {
            PhotoEventService().notifyError(
              'success',
              'Photo processing completed successfully',
              photoPath: sourcePath,
            );

            try {
              final webpFile = File(outputPath);
              if (await webpFile.exists()) {
                await webpFile.delete();
                developer.log(
                  'Deleted temporary WebP file: $outputPath',
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
          final error = 'Error processing image: $e';
          developer.log(error, name: 'PhotoProcessorService');
          PhotoEventService().notifyError(
            'processing',
            error,
            photoPath: sourcePath,
          );
          return null;
        }
      } catch (e) {
        final error = 'Error creating temporary directory: $e';
        developer.log(error, name: 'PhotoProcessorService');
        PhotoEventService().notifyError(
          'processing',
          error,
          photoPath: sourcePath,
        );
        return null;
      }
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

  bool _isValidAspectRatio(int width, int height) {
    const tolerance = 0.01;
    final ratio = width / height;
    final ratio16_9 = 16.0 / 9.0;
    final ratio9_16 = 9.0 / 16.0;

    return (ratio - ratio16_9).abs() < tolerance ||
        (ratio - ratio9_16).abs() < tolerance;
  }

  Future<img.Image?> _decodeImage(Uint8List bytes) async {
    return await compute((Uint8List bytes) {
      return img.decodeImage(bytes);
    }, bytes);
  }

  Future<img.Image> _resizeImageIfNeeded(
    img.Image image,
    int maxDimension,
  ) async {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }

    return await compute((Map<String, dynamic> params) {
      final img.Image image = params['image'];
      final int maxDim = params['maxDim'];

      int newWidth, newHeight;

      if (image.width > image.height) {
        newWidth = maxDim;
        newHeight = (image.height * (maxDim / image.width)).round();
      } else {
        newHeight = maxDim;
        newWidth = (image.width * (maxDim / image.height)).round();
      }

      return img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic,
      );
    }, {'image': image, 'maxDim': maxDimension});
  }

  Future<Uint8List> _encodeToWebP(img.Image image, int quality) async {
    return await _webpEncoderService.encodeToWebP(
      image,
      quality: quality,
      method: 6,
    );
  }

  Map<String, dynamic> _getTierSettings(List<String> badges) {
    if (badges.contains('mega_supporter') ||
        badges.contains('mega_supporter')) {
      return {
        'maxDimension': 7680, // 8K
        'webpQuality': 95,
        'maxSizeBytes': 7864320, // 7.5MB limit
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
