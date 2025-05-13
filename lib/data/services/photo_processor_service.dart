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

class PhotoProcessorService {
  final PhotoUploadService _photoUploadService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final WebpEncoderService _webpEncoderService;

  PhotoProcessorService({
    PhotoUploadService? photoUploadService,
    PhotoMetadataRepository? photoMetadataRepository,
    WebpEncoderService? webpEncoderService,
  }) : _photoUploadService = photoUploadService ?? PhotoUploadService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _webpEncoderService = webpEncoderService ?? WebpEncoderService();

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

          final processedImage = await _resizeImageIfNeeded(image);
          developer.log(
            'Image resized to ${processedImage.width}x${processedImage.height}',
            name: 'PhotoProcessorService',
          );

          final webpBytes = await _encodeToWebP(processedImage, 85);
          developer.log(
            'Encoded to WebP: ${webpBytes.length} bytes',
            name: 'PhotoProcessorService',
          );

          await File(outputPath).writeAsBytes(webpBytes);
          developer.log(
            'Saved WebP file to: $outputPath',
            name: 'PhotoProcessorService',
          );

          final outputFile = File(outputPath);
          final stats = outputFile.statSync();
          final creationTimeMs = stats.modified.millisecondsSinceEpoch;

          final photoMetadata = PhotoMetadata(
            takenDate: creationTimeMs,
            filename: path.basename(outputPath),
            views: 0,
            world: metadata?.world,
            players: metadata?.players ?? [],
            localPath: outputPath,
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
            photoPath: outputPath,
          );

          if (config.uploadEnabled) {
            developer.log(
              'Uploading photo: ${path.basename(outputPath)}',
              name: 'PhotoProcessorService',
            );
            PhotoEventService().notifyError(
              'info',
              'Starting upload process...',
              photoPath: outputPath,
            );

            final uploadSuccess = await _photoUploadService.uploadPhoto(
              outputPath,
              config,
              metadata,
            );

            if (uploadSuccess) {
              developer.log(
                'Photo uploaded successfully',
                name: 'PhotoProcessorService',
              );

              final updatedMetadata = await _photoMetadataRepository
                  .getPhotoMetadataForFile(outputPath);
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
                  photoPath: outputPath,
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
              photoPath: outputPath,
            );
          }
          return outputPath;
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

  Future<img.Image> _resizeImageIfNeeded(img.Image image) async {
    const maxDimension = 1080;

    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }

    return await compute((img.Image image) {
      int newWidth, newHeight;

      if (image.width > image.height) {
        if (image.height > maxDimension) {
          newHeight = maxDimension;
          newWidth = (image.width * (maxDimension / image.height)).round();
        } else {
          newWidth = image.width;
          newHeight = image.height;
        }
      } else {
        if (image.width > maxDimension) {
          newWidth = maxDimension;
          newHeight = (image.height * (maxDimension / image.width)).round();
        } else {
          newWidth = image.width;
          newHeight = image.height;
        }
      }

      return img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic,
      );
    }, image);
  }

  Future<Uint8List> _encodeToWebP(img.Image image, int quality) async {
    return await _webpEncoderService.encodeToWebP(
      image,
      quality: quality,
      method: 6,
    );
  }
}

class EncoderParams {
  final img.Image image;
  final int quality;

  EncoderParams(this.image, this.quality);
}
