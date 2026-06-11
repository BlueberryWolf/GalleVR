import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/native/gallevr_native.dart';
import '../../core/webp/webp_encoder_service.dart';
import '../models/photo_metadata.dart';
import '../models/log_metadata.dart';
import '../models/config_model.dart';
import '../repositories/photo_metadata_repository.dart';
import 'photo_upload_service.dart';
import 'vrchat_service.dart';

class MassUploadService {
  final PhotoUploadService _photoUploadService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final WebpEncoderService _webpEncoderService;
  final VRChatService _vrchatService;

  MassUploadService({
    PhotoUploadService? photoUploadService,
    PhotoMetadataRepository? photoMetadataRepository,
    WebpEncoderService? webpEncoderService,
    VRChatService? vrchatService,
  }) : _photoUploadService = photoUploadService ?? PhotoUploadService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _webpEncoderService = webpEncoderService ?? WebpEncoderService(),
       _vrchatService = vrchatService ?? VRChatService();

  Future<MassUploadResult> processFile(
    String filePath,
    ConfigModel config,
  ) async {
    developer.log('Mass uploading file: $filePath', name: 'MassUploadService');

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return MassUploadResult.error('File not found');
      }

      PhotoMetadata? metadata = await _photoMetadataRepository
          .getPhotoMetadataForFile(filePath);
      if (metadata != null && metadata.world != null) {
        metadata = metadata.copyWith(isEdited: true);
        developer.log(
          'Metadata recovered via filename/database match for ${path.basename(filePath)}',
          name: 'MassUploadService',
        );
      }

      if (metadata == null || metadata.world == null) {
        return MassUploadResult.error(
          'No world/player metadata found for this photo',
        );
      }

      final authData = await _vrchatService.loadAuthData();
      final badges =
          authData?.badges.map((b) => b.toLowerCase()).toList() ?? [];
      final tier = _getTierSettings(badges);
      final int maxDimension = tier['maxDimension']!;
      final int webpQuality = tier['webpQuality']!;
      final int maxSizeBytes = tier['maxSizeBytes']!;

      final String tempPath = path.join(
        Directory.systemTemp.path,
        'gallevr_mass_${DateTime.now().microsecondsSinceEpoch}_${path.basenameWithoutExtension(filePath)}.webp',
      );

      if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
        developer.log(
          'Using fast-path direct cwebp/native encoding for mass upload: $filePath',
          name: 'MassUploadService',
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
            name: 'MassUploadService',
          );
        }

        if (width <= 0 || height <= 0) {
          return MassUploadResult.error(
            'Failed to determine image dimensions from header',
          );
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

        await _webpEncoderService.encodeFileToWebP(
          filePath,
          tempPath,
          quality: webpQuality,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          maxSizeBytes: scaledMaxSizeBytes,
          originalWidth: width,
          originalHeight: height,
        );
      } else {
        Uint8List? webpBytes;
        try {
          final bytes = await file.readAsBytes();
          final image = await compute(img.decodeImage, bytes);

          if (image == null) {
            return MassUploadResult.error('Failed to decode image');
          }

          int targetWidth = image.width;
          int targetHeight = image.height;
          img.Image processedImage = image;

          if (image.width > maxDimension || image.height > maxDimension) {
            if (image.width > image.height) {
              targetWidth = maxDimension;
              targetHeight =
                  (image.height * (maxDimension / image.width)).round();
            } else {
              targetHeight = maxDimension;
              targetWidth =
                  (image.width * (maxDimension / image.height)).round();
            }
            processedImage = await compute((Map<String, dynamic> params) {
              final img.Image imgObj = params['image'];
              final int w = params['w'];
              final int h = params['h'];
              return img.copyResize(imgObj, width: w, height: h);
            }, {'image': image, 'w': targetWidth, 'h': targetHeight});
          }

          final int processedPixels =
              processedImage.width * processedImage.height;
          final int maxTierPixels = tier['maxTierPixels']!;

          int scaledMaxSizeBytes =
              (maxSizeBytes * (processedPixels / maxTierPixels)).round();
          scaledMaxSizeBytes = scaledMaxSizeBytes.clamp(153600, maxSizeBytes);
          if (scaledMaxSizeBytes > maxSizeBytes) {
            scaledMaxSizeBytes = maxSizeBytes;
          }

          webpBytes = await _webpEncoderService.encodeToWebP(
            processedImage,
            quality: webpQuality,
            method: 6,
          );

          if (webpBytes.length > scaledMaxSizeBytes) {
            int currentQuality = webpQuality;
            while (webpBytes!.length > scaledMaxSizeBytes &&
                currentQuality > 50) {
              currentQuality -= 10;
              if (currentQuality < 50) currentQuality = 50;
              webpBytes = await _webpEncoderService.encodeToWebP(
                processedImage,
                quality: currentQuality,
                method: 6,
              );
              if (currentQuality <= 50) break;
            }
          }
        } catch (e) {
          return MassUploadResult.error('Re-encoding failed: $e');
        }

        await File(tempPath).writeAsBytes(webpBytes!);
      }

      final logMetadata = LogMetadata(
        world: metadata.world,
        players: metadata.players,
      );

      final success = await _photoUploadService.uploadPhoto(
        tempPath,
        config,
        logMetadata,
        metadata: metadata,
        originalPath: filePath,
        deleteFileOnComplete: true,
      );

      if (success) {
        return MassUploadResult.success(metadata);
      } else {
        return MassUploadResult.error('Upload failed');
      }
    } catch (e) {
      return MassUploadResult.error('Unexpected error: $e');
    }
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

class MassUploadResult {
  final bool success;
  final String? errorMessage;
  final PhotoMetadata? metadata;

  MassUploadResult.success(this.metadata) : success = true, errorMessage = null;
  MassUploadResult.error(this.errorMessage) : success = false, metadata = null;
}
