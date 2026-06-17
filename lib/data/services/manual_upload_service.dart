import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/config_model.dart';
import '../models/photo_metadata.dart';
import '../models/verification_models.dart';
import '../repositories/photo_metadata_repository.dart';
import '../../core/audio/sound_service.dart';
import '../../core/webp/webp_encoder_service.dart';
import 'app_service_manager.dart';
import 'photo_event_service.dart';
import 'tos_service.dart';
import 'vrchat_service.dart';

/// Service for manually uploading individual photos
class ManualUploadService {
  final VRChatService _vrchatService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final SoundService _soundService;
  final TOSService _tosService;
  final WebpEncoderService _webpEncoderService;

  ManualUploadService({
    VRChatService? vrchatService,
    PhotoMetadataRepository? photoMetadataRepository,
    SoundService? soundService,
    TOSService? tosService,
    WebpEncoderService? webpEncoderService,
  }) : _vrchatService = vrchatService ?? VRChatService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _soundService = soundService ?? AppServiceManager().soundService,
       _tosService = tosService ?? TOSService(),
       _webpEncoderService = webpEncoderService ?? WebpEncoderService();

  /// Manually upload a photo with compression to WebP
  /// Returns the gallery URL if successful, null otherwise
  Future<String?> uploadPhoto(
    String photoPath,
    ConfigModel config, {
    Function(String)? onStatusUpdate,
    Function(double)? onProgress,
  }) async {
    final filename = path.basename(photoPath);
    developer.log(
      'Starting manual upload for photo: $filename',
      name: 'ManualUploadService',
    );

    try {
      onStatusUpdate?.call('Checking authentication...');
      onProgress?.call(0.1);

      onStatusUpdate?.call('Loading photo metadata...');
      onProgress?.call(0.1);

      // Get existing metadata - it must already exist with valid world/player info
      PhotoMetadata? photoMetadata = await _photoMetadataRepository
          .getPhotoMetadataForFile(photoPath);

      if (photoMetadata == null) {
        final error =
            'No metadata found for this photo. Only photos with valid metadata can be uploaded.';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      final isResonitePhoto = (photoMetadata.application == 'Resonite') ||
          (config.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(config.resonitePhotosDirectory, photoPath));

      if (isResonitePhoto && photoMetadata.application != 'Resonite') {
        photoMetadata = photoMetadata.copyWith(application: 'Resonite');
      }

      // Check authentication
      final primaryAuth = await _vrchatService.loadAuthData();
      final secondaryAuth = await _vrchatService.loadAuthDataSecondary();

      AuthData? uploadAuth;
      if (isResonitePhoto) {
        if (primaryAuth != null && primaryAuth.userId.startsWith('U-')) {
          uploadAuth = primaryAuth;
        } else if (secondaryAuth != null &&
            secondaryAuth.userId.startsWith('U-')) {
          uploadAuth = secondaryAuth;
        }
      } else {
        if (primaryAuth != null && !primaryAuth.userId.startsWith('U-')) {
          uploadAuth = primaryAuth;
        } else if (secondaryAuth != null &&
            !secondaryAuth.userId.startsWith('U-')) {
          uploadAuth = secondaryAuth;
        }
      }

      if (uploadAuth == null) {
        final error =
            'No authentication data found for ${isResonitePhoto ? "Resonite" : "VRChat"}. Please log in.';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      onStatusUpdate?.call('Verifying account...');
      onProgress?.call(0.25);

      // Check verification status
      developer.log(
        'Checking verification status before manual upload for ${uploadAuth.userId}',
        name: 'ManualUploadService',
      );
      final isVerified = await _vrchatService.checkVerificationStatus(uploadAuth);
      if (!isVerified) {
        final error =
            'Your account ${uploadAuth.displayName} is not verified. Please verify your account in the Account tab';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      onStatusUpdate?.call('Checking Terms of Service...');
      onProgress?.call(0.35);

      // Check if user needs to accept TOS
      developer.log(
        'Checking TOS acceptance status before manual upload',
        name: 'ManualUploadService',
      );
      final needsToAcceptTOS = await _tosService.needsToAcceptTOS();
      if (needsToAcceptTOS) {
        final error =
            'You need to accept the Terms of Service before uploading photos.';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      // Check if photo has valid metadata (world or players for VRChat, or isResonitePhoto)
      final hasValidMetadata = isResonitePhoto ||
          photoMetadata.world != null ||
          photoMetadata.players.isNotEmpty;
      if (!hasValidMetadata) {
        final error =
            'Photo must have valid metadata (world or player information) to be uploaded';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      if (isResonitePhoto || photoMetadata.application == 'Resonite') {
        if (photoMetadata.cameraManufacturer == null ||
            photoMetadata.cameraManufacturer!.isEmpty) {
          final error =
              'Resonite screenshot detected (no CameraManufacturer metadata). Skipping upload.';
          developer.log(error, name: 'ManualUploadService');
          PhotoEventService().notifyError(
            'upload',
            error,
            photoPath: photoPath,
          );
          throw Exception(error);
        }
      }

      developer.log(
        'Found valid metadata for manual upload: ${photoMetadata.filename} (World: ${photoMetadata.world?.name}, Players: ${photoMetadata.players.length})',
        name: 'ManualUploadService',
      );

      onStatusUpdate?.call('Processing and compressing photo...');
      onProgress?.call(0.5);

      // Process and compress the photo to WebP
      PhotoEventService().notifyError(
        'info',
        'Processing photo for manual upload...',
        photoPath: photoPath,
      );

      final badges =
          uploadAuth.badges.map((b) => b.toString().toLowerCase()).toList();
      final webpPath = await _processPhotoToWebP(photoPath, badges);
      if (webpPath == null) {
        final error = 'Failed to process photo to WebP format';
        PhotoEventService().notifyError(
          'processing',
          error,
          photoPath: photoPath,
        );
        throw Exception(error);
      }

      onStatusUpdate?.call('Uploading photo...');
      onProgress?.call(0.75);

      PhotoEventService().notifyError(
        'info',
        'Uploading compressed photo to gallery...',
        photoPath: photoPath,
      );

      // Upload the WebP file
      final galleryUrl = await _uploadWebPFile(
        webpPath,
        photoMetadata,
        uploadAuth,
      );

      if (galleryUrl != null) {
        onStatusUpdate?.call('Updating metadata...');
        onProgress?.call(0.9);

        // Update the original photo's metadata with gallery URL
        // Keep the original localPath pointing to the source photo
        final updatedMetadata = photoMetadata.copyWith(
          galleryUrl: galleryUrl,
          localPath: photoPath, // Ensure we keep the original photo path
        );
        await _photoMetadataRepository.savePhotoMetadata(updatedMetadata);

        developer.log(
          'Manual upload successful, gallery URL: $galleryUrl',
          name: 'ManualUploadService',
        );

        PhotoEventService().notifyError(
          'success',
          'Photo uploaded successfully via manual upload',
          photoPath: photoPath,
        );

        // Notify that the photo was uploaded
        PhotoEventService().notifyPhotoUploaded(photoPath);

        onStatusUpdate?.call('Upload complete!');
        onProgress?.call(1.0);

        // Play upload sound
        await _soundService.playUploadSound(config);

        // Auto-copy gallery URL if enabled
        if (config.autoCopyGalleryUrl && galleryUrl.isNotEmpty) {
          try {
            await Clipboard.setData(ClipboardData(text: galleryUrl));
            developer.log(
              'Copied gallery URL to clipboard: $galleryUrl',
              name: 'ManualUploadService',
            );
            PhotoEventService().notifyError(
              'info',
              'Gallery URL copied to clipboard',
              photoPath: photoPath,
            );
          } catch (e) {
            developer.log(
              'Error copying gallery URL to clipboard: $e',
              name: 'ManualUploadService',
              error: e,
            );
          }
        }

        // Clean up temporary WebP file
        try {
          await File(webpPath).delete();
        } catch (e) {
          developer.log(
            'Error cleaning up temporary file: $e',
            name: 'ManualUploadService',
          );
        }

        return galleryUrl;
      } else {
        final error = 'Upload failed - no gallery URL returned';
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }
    } catch (e) {
      final error = 'Manual upload failed: $e';
      developer.log(error, name: 'ManualUploadService', error: e);
      PhotoEventService().notifyError('upload', error, photoPath: photoPath);
      onStatusUpdate?.call('Upload failed: $e');
      return null;
    }
  }

  /// Process a photo to WebP format with compression
  Future<String?> _processPhotoToWebP(
    String sourcePath,
    List<String> badges,
  ) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        developer.log(
          'Source file does not exist: $sourcePath',
          name: 'ManualUploadService',
        );
        return null;
      }

      // Create temporary directory for processing
      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory(
        path.join(
          tempDir.path,
          'GalleVR-ManualUpload',
          DateTime.now().toIso8601String().split('T')[0],
        ),
      );

      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final fileName = path.basenameWithoutExtension(sourcePath);
      final outputPath = path.join(outputDir.path, '$fileName.webp');

      final tier = _getTierSettings(badges);
      final int maxDimension = tier['maxDimension']!;
      final int webpQuality = tier['webpQuality']!;
      final int maxSizeBytes = tier['maxSizeBytes']!;
      final int maxTierPixels = tier['maxTierPixels']!;

      if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
        developer.log(
          'Using fast-path direct cwebp/native encoding for manual upload: $sourcePath',
          name: 'ManualUploadService',
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
            name: 'ManualUploadService',
          );
        }

        if (width <= 0 || height <= 0) {
          throw Exception('Failed to determine image dimensions from header');
        }

        if (!_isValidAspectRatio(width, height)) {
          final ratio = (width / height).toStringAsFixed(2);
          final error = 'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
          developer.log(error, name: 'ManualUploadService');
          PhotoEventService().notifyError(
            'processing',
            error,
            photoPath: sourcePath,
          );
          throw Exception(error);
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

        int scaledMaxSizeBytes =
            (maxSizeBytes * (processedPixels / maxTierPixels)).round();
        scaledMaxSizeBytes = scaledMaxSizeBytes.clamp(153600, maxSizeBytes);
        if (scaledMaxSizeBytes > maxSizeBytes) {
          scaledMaxSizeBytes = maxSizeBytes;
        }

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
          'Fast-path direct encoding completed successfully: $outputPath',
          name: 'ManualUploadService',
        );
        return outputPath;
      }

      // Read and decode the image (fallback)
      final bytes = await file.readAsBytes();
      final image = await compute((Uint8List bytes) {
        return img.decodeImage(bytes);
      }, bytes);

      if (image == null) {
        developer.log(
          'Failed to decode image: $sourcePath',
          name: 'ManualUploadService',
        );
        return null;
      }

      // Validate aspect ratio (16:9 or 9:16)
      if (!_isValidAspectRatio(image.width, image.height)) {
        final ratio = (image.width / image.height).toStringAsFixed(2);
        final error = 'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError(
          'processing',
          error,
          photoPath: sourcePath,
        );
        throw Exception(error);
      }

      // Resize if needed
      final processedImage = await _resizeImageIfNeeded(image, maxDimension);
      developer.log(
        'Image resized to ${processedImage.width}x${processedImage.height}',
        name: 'ManualUploadService',
      );

      final int processedPixels = processedImage.width * processedImage.height;

      int scaledMaxSizeBytes =
          (maxSizeBytes * (processedPixels / maxTierPixels)).round();
      scaledMaxSizeBytes = scaledMaxSizeBytes.clamp(153600, maxSizeBytes);
      if (scaledMaxSizeBytes > maxSizeBytes) {
        scaledMaxSizeBytes = maxSizeBytes;
      }

      // Encode to WebP with size constraints
      var webpBytes = await _webpEncoderService.encodeToWebP(
        processedImage,
        quality: webpQuality,
        method: 6,
      );

      if (webpBytes.length > scaledMaxSizeBytes) {
        int currentQuality = webpQuality;
        while (webpBytes.length > scaledMaxSizeBytes && currentQuality > 50) {
          currentQuality -= 10;
          if (currentQuality < 50) currentQuality = 50;
          webpBytes = await _webpEncoderService.encodeToWebP(
            processedImage,
            quality: currentQuality,
            method: 6,
          );
          if (currentQuality == 50) break;
        }
      }

      developer.log(
        'Encoded to WebP: ${webpBytes.length} bytes',
        name: 'ManualUploadService',
      );

      // Save the WebP file
      await File(outputPath).writeAsBytes(webpBytes);
      developer.log(
        'Saved WebP file to: $outputPath',
        name: 'ManualUploadService',
      );

      return outputPath;
    } catch (e) {
      developer.log(
        'Error processing photo to WebP: $e',
        name: 'ManualUploadService',
        error: e,
      );
      return null;
    }
  }

  /// Upload the WebP file to the server
  Future<String?> _uploadWebPFile(
    String webpPath,
    PhotoMetadata metadata,
    dynamic authData,
  ) async {
    try {
      final file = File(webpPath);
      if (!await file.exists()) {
        developer.log(
          'WebP file does not exist: $webpPath',
          name: 'ManualUploadService',
        );
        return null;
      }

      final fileBytes = await file.readAsBytes();
      developer.log(
        'Read ${fileBytes.length} bytes from WebP file',
        name: 'ManualUploadService',
      );

      final metadataJson = json.encode(metadata.toJson());
      final metadataBase64 = base64.encode(utf8.encode(metadataJson));

      final uploadUrl = Uri.parse(
        'https://api.gallevr.app/vrchat/photo/upload?user=${Uri.encodeComponent(authData.userId)}&type=webp',
      );

      final request = http.Request('POST', uploadUrl);
      request.bodyBytes = fileBytes;
      request.headers['Content-Type'] = 'application/octet-stream';
      request.headers['Authorization'] = 'Bearer ${authData.accessKey}';
      request.headers['metadata'] = metadataBase64;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final galleryUrl = response.body.trim();
        developer.log(
          'Manual upload successful, gallery URL: $galleryUrl',
          name: 'ManualUploadService',
        );
        return galleryUrl;
      } else {
        developer.log(
          'Upload failed with status ${response.statusCode}: ${response.body}',
          name: 'ManualUploadService',
        );
        return null;
      }
    } catch (e) {
      developer.log(
        'Network error during manual upload: $e',
        name: 'ManualUploadService',
        error: e,
      );
      return null;
    }
  }

  /// Check if the image has a valid aspect ratio (16:9 or 9:16)
  bool _isValidAspectRatio(int width, int height) {
    const tolerance = 0.01;
    final ratio = width / height;
    final ratio16_9 = 16.0 / 9.0;
    final ratio9_16 = 9.0 / 16.0;

    return (ratio - ratio16_9).abs() < tolerance ||
        (ratio - ratio9_16).abs() < tolerance;
  }

  /// Resize image if it exceeds maxDimension while maintaining aspect ratio
  Future<img.Image> _resizeImageIfNeeded(
    img.Image image,
    int maxDimension,
  ) async {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }

    return await compute((Map<String, dynamic> params) {
      final img.Image imgObj = params['image'];
      final int maxDim = params['maxDimension'];
      int newWidth, newHeight;

      if (imgObj.width > imgObj.height) {
        if (imgObj.height > maxDim) {
          newHeight = maxDim;
          newWidth = (imgObj.width * (maxDim / imgObj.height)).round();
        } else {
          newWidth = imgObj.width;
          newHeight = imgObj.height;
        }
      } else {
        if (imgObj.width > maxDim) {
          newWidth = maxDim;
          newHeight = (imgObj.height * (maxDim / imgObj.width)).round();
        } else {
          newWidth = imgObj.width;
          newHeight = imgObj.height;
        }
      }

      return img.copyResize(
        imgObj,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic,
      );
    }, {'image': image, 'maxDimension': maxDimension});
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
