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

      // Check authentication
      final authData = await _vrchatService.loadAuthData();
      if (authData == null) {
        final error = 'No authentication data found. Please log in to upload photos';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      onStatusUpdate?.call('Verifying account...');
      onProgress?.call(0.2);

      // Check verification status
      developer.log(
        'Checking verification status before manual upload',
        name: 'ManualUploadService',
      );
      final isVerified = await _vrchatService.checkVerificationStatus(authData);
      if (!isVerified) {
        final error = 'Your account is not verified. Please verify your account in the Account tab';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        await _vrchatService.logout();
        throw Exception(error);
      }

      onStatusUpdate?.call('Checking Terms of Service...');
      onProgress?.call(0.3);

      // Check if user needs to accept TOS
      developer.log(
        'Checking TOS acceptance status before manual upload',
        name: 'ManualUploadService',
      );
      final needsToAcceptTOS = await _tosService.needsToAcceptTOS();
      if (needsToAcceptTOS) {
        final error = 'You need to accept the Terms of Service before uploading photos.';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      onStatusUpdate?.call('Loading photo metadata...');
      onProgress?.call(0.4);

      // Get existing metadata - it must already exist with valid world/player info
      PhotoMetadata? photoMetadata = await _photoMetadataRepository.getPhotoMetadataForFile(photoPath);
      
      if (photoMetadata == null) {
        final error = 'No metadata found for this photo. Only photos with valid metadata can be uploaded.';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
      }

      // Check if photo has valid metadata (world or players)
      final hasValidMetadata = photoMetadata.world != null || photoMetadata.players.isNotEmpty;
      if (!hasValidMetadata) {
        final error = 'Photo must have valid metadata (world or player information) to be uploaded';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        throw Exception(error);
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
      
      final webpPath = await _processPhotoToWebP(photoPath);
      if (webpPath == null) {
        final error = 'Failed to process photo to WebP format';
        PhotoEventService().notifyError('processing', error, photoPath: photoPath);
        throw Exception(error);
      }

      onStatusUpdate?.call('Uploading photo...');
      onProgress?.call(0.7);

      PhotoEventService().notifyError(
        'info',
        'Uploading compressed photo to gallery...',
        photoPath: photoPath,
      );

      // Upload the WebP file
      final galleryUrl = await _uploadWebPFile(webpPath, photoMetadata, authData);
      
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
  Future<String?> _processPhotoToWebP(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        developer.log('Source file does not exist: $sourcePath', name: 'ManualUploadService');
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

      // Read and decode the image
      final bytes = await file.readAsBytes();
      final image = await compute((Uint8List bytes) {
        return img.decodeImage(bytes);
      }, bytes);

      if (image == null) {
        developer.log('Failed to decode image: $sourcePath', name: 'ManualUploadService');
        return null;
      }

      // Validate aspect ratio (16:9 or 9:16)
      if (!_isValidAspectRatio(image.width, image.height)) {
        final ratio = (image.width / image.height).toStringAsFixed(2);
        final error = 'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)';
        developer.log(error, name: 'ManualUploadService');
        PhotoEventService().notifyError('processing', error, photoPath: sourcePath);
        throw Exception(error);
      }

      // Resize if needed (max 1080p)
      final processedImage = await _resizeImageIfNeeded(image);
      developer.log(
        'Image resized to ${processedImage.width}x${processedImage.height}',
        name: 'ManualUploadService',
      );

      // Encode to WebP with size constraints
      final webpBytes = await _webpEncoderService.encodeToWebP(
        processedImage,
        quality: 85,
        method: 6,
      );

      developer.log(
        'Encoded to WebP: ${webpBytes.length} bytes',
        name: 'ManualUploadService',
      );

      // Save the WebP file
      await File(outputPath).writeAsBytes(webpBytes);
      developer.log('Saved WebP file to: $outputPath', name: 'ManualUploadService');

      return outputPath;
    } catch (e) {
      developer.log('Error processing photo to WebP: $e', name: 'ManualUploadService', error: e);
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
        developer.log('WebP file does not exist: $webpPath', name: 'ManualUploadService');
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
        'https://api.blueberry.coffee/vrchat/photo/upload?user=${Uri.encodeComponent(authData.userId)}&type=webp',
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
        developer.log('Manual upload successful, gallery URL: $galleryUrl', name: 'ManualUploadService');
        return galleryUrl;
      } else {
        developer.log(
          'Upload failed with status ${response.statusCode}: ${response.body}',
          name: 'ManualUploadService',
        );
        return null;
      }
    } catch (e) {
      developer.log('Network error during manual upload: $e', name: 'ManualUploadService', error: e);
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

  /// Resize image if it exceeds 1080p while maintaining aspect ratio
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
}