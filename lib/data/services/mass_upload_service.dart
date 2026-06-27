import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;

import '../models/photo_metadata.dart';
import '../models/config_model.dart';
import '../repositories/photo_metadata_repository.dart';
import 'photo_processor_service.dart';
import 'photo_upload_service.dart';
import 'vrchat_service.dart';

class MassUploadService {
  final PhotoUploadService _photoUploadService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final VRChatService _vrchatService;

  MassUploadService({
    PhotoUploadService? photoUploadService,
    PhotoMetadataRepository? photoMetadataRepository,
    VRChatService? vrchatService,
  }) : _photoUploadService = photoUploadService ?? PhotoUploadService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
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

      final isResonitePhoto = (metadata.application == 'Resonite') ||
          (config.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(config.resonitePhotosDirectory, filePath));

      final authData = await _vrchatService.loadAuthData();
      final secondaryAuth = await _vrchatService.loadAuthDataSecondary();

      final uploadAuth = isResonitePhoto
          ? (authData?.userId.startsWith('U-') == true ? authData : secondaryAuth)
          : (authData?.userId.startsWith('U-') == false ? authData : secondaryAuth);

      if (uploadAuth == null) {
        return MassUploadResult.error(
          'No authentication data found for ${isResonitePhoto ? "Resonite" : "VRChat"}. Please log in.',
        );
      }

      final badges = uploadAuth.badges.map((b) => b.toString().toLowerCase()).toList();

      final webpPath = await PhotoProcessorService().compressPhotoToWebP(
        filePath,
        badges,
        isResonite: isResonitePhoto,
      );

      if (webpPath == null) {
        return MassUploadResult.error('Failed to process photo to WebP format');
      }

      final success = await _photoUploadService.uploadPhoto(
        webpPath,
        config,
        null,
        metadata: metadata,
        originalPath: filePath,
        deleteFileOnComplete: true,
      );

      if (success) {
        final updated = await _photoMetadataRepository.getPhotoMetadataForFile(filePath);
        return MassUploadResult.success(updated ?? metadata);
      } else {
        return MassUploadResult.error('Upload failed');
      }
    } catch (e) {
      return MassUploadResult.error('Unexpected error: $e');
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
