import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/webp/webp_encoder_service.dart';
import '../../core/native/gallevr_native.dart';
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

          // Determine quality settings based on user tier
          final authData = await _vrchatService.loadAuthData();
          final badges = authData?.badges.map((b) => b.toLowerCase()).toList() ?? [];
          
          int maxDimension = 1920;
          int webpQuality = 85;

          if (badges.contains('mega_supporter')) {
            maxDimension = 7680; // 8K
            webpQuality = 95;
            developer.log('User is Mega Supporter: 8K limit, 95 quality', name: 'PhotoProcessorService');
          } else if (badges.contains('super_supporter')) {
            maxDimension = 3840; // 4K
            webpQuality = 92;
            developer.log('User is Super Supporter: 4K limit, 92 quality', name: 'PhotoProcessorService');
          } else if (badges.contains('supporter') || badges.contains('donator')) {
            maxDimension = 2560; // 2K (1440p)
            webpQuality = 90;
            developer.log('User is Supporter: 1440p limit, 90 quality', name: 'PhotoProcessorService');
          } else {
            developer.log('User is standard: 1080p limit, 85 quality', name: 'PhotoProcessorService');
          }

          final processedImage = await _resizeImageIfNeeded(image, maxDimension);
          developer.log(
            'Image processed to ${processedImage.width}x${processedImage.height}',
            name: 'PhotoProcessorService',
          );

          Uint8List webpBytes = await _encodeToWebP(processedImage, webpQuality);
          
          final bool isSupporter = badges.any((b) => [
            'mega_supporter', 'super_supporter', 'supporter', 'donator'
          ].contains(b));

          if (!isSupporter && webpBytes.length > 153600) {
            int currentQuality = webpQuality;
            developer.log('Initial encode too large for standard user (${webpBytes.length} bytes), starting iterative compression...', name: 'PhotoProcessorService');
            
            while (webpBytes.length > 153600 && currentQuality > 50) {
              currentQuality -= 10;
              if (currentQuality < 50) currentQuality = 50;
              webpBytes = await _encodeToWebP(processedImage, currentQuality);
              developer.log('Retry quality $currentQuality produced ${webpBytes.length} bytes', name: 'PhotoProcessorService');
              if (currentQuality <= 50) break;
            }
          }

          developer.log(
            'Final WebP: ${webpBytes.length} bytes (Quality: $webpQuality / Supporter: $isSupporter)',
            name: 'PhotoProcessorService',
          );

          await File(outputPath).writeAsBytes(webpBytes);
          developer.log(
            'Saved WebP file to: $outputPath',
            name: 'PhotoProcessorService',
          );

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
              'Uploading photo: ${path.basename(outputPath)}',
              name: 'PhotoProcessorService',
            );
            PhotoEventService().notifyError(
              'info',
              'Starting upload process...',
              photoPath: sourcePath,
            );

            final uploadSuccess = await _photoUploadService.uploadPhoto(
              outputPath,
              config,
              metadata,
              metadata: photoMetadata,
              originalPath: sourcePath,
            );

            if (uploadSuccess) {
              developer.log(
                'Photo uploaded successfully',
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
                  'No gallery URL found after upload',
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
                'Photo upload failed',
                name: 'PhotoProcessorService',
              );
            }
          }

          if (!config.uploadEnabled) {
            PhotoEventService().notifyError(
              'success',
              'Photo processing completed successfully',
              photoPath: sourcePath,
            );
          }
          // clean up the WebP file after processing/uploading
          try {
            final webpFile = File(outputPath);
            if (await webpFile.exists()) {
              await webpFile.delete();
              developer.log('Deleted temporary WebP file: $outputPath', name: 'PhotoProcessorService');
            }
          } catch (e) {
            developer.log('Error deleting temporary WebP file: $e', name: 'PhotoProcessorService');
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

  Future<img.Image> _resizeImageIfNeeded(img.Image image, int maxDimension) async {
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
}
