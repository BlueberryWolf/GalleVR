import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

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

  Future<MassUploadResult> processFile(String filePath, ConfigModel config) async {
    developer.log('Mass uploading file: $filePath', name: 'MassUploadService');
    
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return MassUploadResult.error('File not found');
      }

      PhotoMetadata? metadata = await _photoMetadataRepository.getPhotoMetadataForFile(filePath);
      if (metadata != null && metadata.world != null) {
        metadata = metadata.copyWith(isEdited: true);
        developer.log('Metadata recovered via filename/database match for ${path.basename(filePath)}', name: 'MassUploadService');
      }

      if (metadata == null || metadata.world == null) {
        return MassUploadResult.error('No world/player metadata found for this photo');
      }

      Uint8List? webpBytes;
      try {
        final bytes = await file.readAsBytes();
        final image = await compute(img.decodeImage, bytes);
        
        if (image == null) return MassUploadResult.error('Failed to decode image');

        webpBytes = await _webpEncoderService.encodeToWebP(
          image,
          quality: 90,
          method: 6,
        );
      } catch (e) {
        return MassUploadResult.error('Re-encoding failed: $e');
      }

      final tempDir = await Directory.systemTemp.createTemp('gallevr_mass');
      final tempPath = path.join(tempDir.path, '${path.basenameWithoutExtension(filePath)}.webp');
      await File(tempPath).writeAsBytes(webpBytes);

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
      );

      await tempDir.delete(recursive: true);

      if (success) {
        return MassUploadResult.success(metadata);
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
