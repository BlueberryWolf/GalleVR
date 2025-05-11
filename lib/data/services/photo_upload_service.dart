import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/config_model.dart';
import '../models/log_metadata.dart';
import '../models/photo_metadata.dart';
import '../models/verification_models.dart';
import '../repositories/photo_metadata_repository.dart';
import '../../core/audio/sound_service.dart';
import 'app_service_manager.dart';
import 'photo_event_service.dart';
import 'vrchat_service.dart';

// Service for uploading photos to the server
class PhotoUploadService {
  final VRChatService _vrchatService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final SoundService _soundService;
  final AppServiceManager _appServiceManager;

  PhotoUploadService({
    VRChatService? vrchatService,
    PhotoMetadataRepository? photoMetadataRepository,
    SoundService? soundService,
    AppServiceManager? appServiceManager,
  }) : _vrchatService = vrchatService ?? VRChatService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _soundService = soundService ?? AppServiceManager().soundService,
       _appServiceManager = appServiceManager ?? AppServiceManager();

  Future<bool> uploadPhoto(
    String photoPath,
    ConfigModel config,
    LogMetadata? logMetadata,
  ) async {
    final filename = path.basename(photoPath);
    developer.log(
      'Starting upload for photo: $filename',
      name: 'PhotoUploadService',
    );

    try {
      if (!config.uploadEnabled) {
        final error = 'Photo uploading is disabled in settings';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        return false;
      }

      final authData = await _vrchatService.loadAuthData();
      if (authData == null) {
        final error =
            'No authentication data found. Please log in to upload photos';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        return false;
      }

      developer.log(
        'Checking verification status before upload',
        name: 'PhotoUploadService',
      );
      final isVerified = await _vrchatService.checkVerificationStatus(authData);
      if (!isVerified) {
        final error =
            'Your account is not verified. Please verify your account in the Account tab';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);

        await _vrchatService.logout();
        return false;
      }

      final photoMetadata = _createPhotoMetadata(photoPath, logMetadata);

      final saveResult = await _photoMetadataRepository.savePhotoMetadata(
        photoMetadata,
      );
      developer.log(
        'Metadata saved locally: $saveResult for ${photoMetadata.filename}',
        name: 'PhotoUploadService',
      );

      final file = File(photoPath);
      if (!await file.exists()) {
        final error = 'Photo file does not exist: $photoPath';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        return false;
      }

      final fileBytes = await file.readAsBytes();
      developer.log(
        'Read ${fileBytes.length} bytes from file',
        name: 'PhotoUploadService',
      );

      final metadataJson = json.encode(photoMetadata.toJson());
      final metadataBase64 = base64.encode(utf8.encode(metadataJson));

      final uploadUrl = Uri.parse(
        'https://api.blueberry.coffee/vrchat/photo/upload?user=${Uri.encodeComponent(authData.userId)}&type=webp',
      );

      final request = http.Request('POST', uploadUrl);
      request.bodyBytes = fileBytes;
      request.headers['Content-Type'] = 'application/octet-stream';
      request.headers['Authorization'] = 'Bearer ${authData.accessKey}';
      request.headers['metadata'] = metadataBase64;

      try {
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          developer.log(
            'Photo uploaded successfully',
            name: 'PhotoUploadService',
          );
          PhotoEventService().notifyError(
            'success',
            'Photo uploaded successfully',
            photoPath: photoPath,
          );

          final galleryUrl = response.body.trim();
          developer.log('Gallery URL: $galleryUrl', name: 'PhotoUploadService');

          final updatedMetadata = photoMetadata.copyWith(
            galleryUrl: galleryUrl,
          );

          final saveResult = await _photoMetadataRepository.savePhotoMetadata(
            updatedMetadata,
          );
          developer.log(
            'Updated metadata with gallery URL, save result: $saveResult',
            name: 'PhotoUploadService',
          );

          final verifiedMetadata = await _photoMetadataRepository
              .getPhotoMetadataForFile(photoPath);
          if (verifiedMetadata?.galleryUrl != null) {
            developer.log(
              'Verified gallery URL was saved: ${verifiedMetadata!.galleryUrl}',
              name: 'PhotoUploadService',
            );
          } else {
            final warning = 'WARNING: Gallery URL was not saved correctly';
            developer.log(warning, name: 'PhotoUploadService');
            PhotoEventService().notifyError(
              'warning',
              warning,
              photoPath: photoPath,
            );
          }

          await _soundService.playUploadSound(config);
          developer.log(
            'Played upload complete sound',
            name: 'PhotoUploadService',
          );

          return true;
        } else {
          final error =
              'Upload failed with status ${response.statusCode}: ${response.body}';
          developer.log(error, name: 'PhotoUploadService');
          PhotoEventService().notifyError(
            'upload',
            error,
            photoPath: photoPath,
          );
          return false;
        }
      } catch (e) {
        final error = 'Network error during upload: $e';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        return false;
      }
    } catch (e) {
      final error = 'Error uploading photo: $e';
      developer.log(error, name: 'PhotoUploadService');
      PhotoEventService().notifyError('upload', error, photoPath: photoPath);
      return false;
    }
  }

  PhotoMetadata _createPhotoMetadata(
    String photoPath,
    LogMetadata? logMetadata,
  ) {
    final file = File(photoPath);
    final stats = file.statSync();
    final creationTimeMs = stats.modified.millisecondsSinceEpoch;

    return PhotoMetadata(
      takenDate: creationTimeMs,
      filename: path.basename(photoPath),
      views: 0,
      world: logMetadata?.world,
      players: logMetadata?.players ?? [],
      localPath: photoPath,
    );
  }
}
