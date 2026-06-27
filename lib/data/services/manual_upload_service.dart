import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;

import '../models/config_model.dart';
import '../models/photo_metadata.dart';
import '../repositories/photo_metadata_repository.dart';
import 'photo_processor_service.dart';
import 'photo_upload_service.dart';
import 'vrchat_service.dart';

/// Service for manually uploading individual photos
class ManualUploadService {
  final VRChatService _vrchatService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final PhotoUploadService _photoUploadService;

  ManualUploadService({
    VRChatService? vrchatService,
    PhotoMetadataRepository? photoMetadataRepository,
    PhotoUploadService? photoUploadService,
  }) : _vrchatService = vrchatService ?? VRChatService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _photoUploadService = photoUploadService ?? PhotoUploadService();

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

      PhotoMetadata? photoMetadata = await _photoMetadataRepository
          .getPhotoMetadataForFile(photoPath);

      if (photoMetadata == null) {
        throw Exception('No metadata found for this photo.');
      }

      final isResonitePhoto = (photoMetadata.application == 'Resonite') ||
          (config.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(config.resonitePhotosDirectory, photoPath));

      final primaryAuth = await _vrchatService.loadAuthData();
      final secondaryAuth = await _vrchatService.loadAuthDataSecondary();

      final uploadAuth = isResonitePhoto
          ? (primaryAuth?.userId.startsWith('U-') == true ? primaryAuth : secondaryAuth)
          : (primaryAuth?.userId.startsWith('U-') == false ? primaryAuth : secondaryAuth);

      if (uploadAuth == null) {
        throw Exception(
          'No authentication data found for ${isResonitePhoto ? "Resonite" : "VRChat"}. Please log in.',
        );
      }

      final badges = uploadAuth.badges.map((b) => b.toString().toLowerCase()).toList();

      onStatusUpdate?.call('Processing and compressing photo...');
      onProgress?.call(0.4);

      final webpPath = await PhotoProcessorService().compressPhotoToWebP(
        photoPath,
        badges,
        isResonite: isResonitePhoto,
      );

      if (webpPath == null) {
        throw Exception('Failed to process photo to WebP format');
      }

      onStatusUpdate?.call('Uploading photo...');
      onProgress?.call(0.7);

      final success = await _photoUploadService.uploadPhoto(
        webpPath,
        config,
        null,
        metadata: photoMetadata,
        originalPath: photoPath,
        deleteFileOnComplete: true,
      );

      if (success) {
        onStatusUpdate?.call('Upload complete!');
        onProgress?.call(1.0);

        final updatedMetadata = await _photoMetadataRepository
            .getPhotoMetadataForFile(photoPath);
        return updatedMetadata?.galleryUrl;
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      final error = 'Manual upload failed: $e';
      developer.log(error, name: 'ManualUploadService', error: e);
      onStatusUpdate?.call('Upload failed: $e');
      return null;
    }
  }
}
