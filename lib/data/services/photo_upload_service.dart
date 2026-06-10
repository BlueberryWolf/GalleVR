import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/config_model.dart';
import '../models/log_metadata.dart';
import '../models/photo_metadata.dart';
import '../repositories/photo_metadata_repository.dart';
import '../../core/audio/sound_service.dart';
import 'app_service_manager.dart';
import 'photo_event_service.dart';
import 'tos_service.dart';
import 'vrchat_service.dart';

// Service for uploading photos to the server
class PhotoUploadService {
  final VRChatService _vrchatService;
  final PhotoMetadataRepository _photoMetadataRepository;
  final SoundService _soundService;
  final TOSService _tosService;

  PhotoUploadService({
    VRChatService? vrchatService,
    PhotoMetadataRepository? photoMetadataRepository,
    SoundService? soundService,
    TOSService? tosService,
  }) : _vrchatService = vrchatService ?? VRChatService(),
       _photoMetadataRepository =
           photoMetadataRepository ?? PhotoMetadataRepository(),
       _soundService = soundService ?? AppServiceManager().soundService,
       _tosService = tosService ?? TOSService();

  Future<bool> uploadPhoto(
    String photoPath,
    ConfigModel config,
    LogMetadata? logMetadata, {
    PhotoMetadata? metadata,
    String? originalPath,
    bool deleteFileOnComplete = false,
  }) async {
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

      // Check if user needs to accept TOS
      developer.log(
        'Checking TOS acceptance status before upload',
        name: 'PhotoUploadService',
      );
      final needsToAcceptTOS = await _tosService.needsToAcceptTOS();
      if (needsToAcceptTOS) {
        final error =
            'You need to accept the Terms of Service before uploading photos.';
        developer.log(error, name: 'PhotoUploadService');
        PhotoEventService().notifyError('upload', error, photoPath: photoPath);
        return false;
      }

      PhotoMetadata photoMetadata =
          metadata ?? _createPhotoMetadata(photoPath, logMetadata);

      if (photoMetadata.application == 'VRChat') {
        photoMetadata = photoMetadata.copyWith(
          players: [
            Player(id: authData.userId, name: authData.displayName ?? authData.userId),
          ],
        );
      }

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

      final metadataJson = json.encode(photoMetadata.toJson());
      final metadataBase64 = base64.encode(utf8.encode(metadataJson));

      // Attempt native curl upload on Windows/Linux for maximum speed and zero Dart heap overhead
      if (Platform.isWindows || Platform.isLinux) {
        try {
          developer.log(
            'Attempting native curl upload for speed and zero Dart heap overhead: $photoPath',
            name: 'PhotoUploadService',
          );
          final uploadUrlStr =
              'https://api.gallevr.app/vrchat/photo/upload?user=${Uri.encodeComponent(authData.userId)}&type=webp';

          final curlArgs = [
            '-s', // Silent mode
            '-X', 'POST',
            uploadUrlStr,
            '-H', 'Content-Type: application/octet-stream',
            '-H', 'Authorization: Bearer ${authData.accessKey}',
            '-H', 'metadata: $metadataBase64',
            '--data-binary', '@$photoPath',
          ];

          final result = await Process.run('curl', curlArgs);
          if (result.exitCode == 0) {
            final galleryUrl = result.stdout.toString().trim();
            if (galleryUrl.startsWith('http://') ||
                galleryUrl.startsWith('https://')) {
              developer.log(
                'Native curl upload succeeded. URL: $galleryUrl',
                name: 'PhotoUploadService',
              );
              return await _handleUploadSuccess(
                galleryUrl,
                photoMetadata,
                photoPath,
                originalPath,
                config,
              );
            } else {
              developer.log(
                'Curl succeeded but response was not a valid URL: $galleryUrl. Falling back to Dart HTTP...',
                name: 'PhotoUploadService',
              );
            }
          } else {
            developer.log(
              'Curl failed with exit code ${result.exitCode}: ${result.stderr}. Falling back to Dart HTTP...',
              name: 'PhotoUploadService',
            );
          }
        } catch (e) {
          developer.log(
            'Failed to execute native curl: $e. Falling back to Dart HTTP...',
            name: 'PhotoUploadService',
          );
        }
      }

      // Fallback path: standard Dart HTTP package upload
      final fileBytes = await file.readAsBytes();
      developer.log(
        'Read ${fileBytes.length} bytes from file for Dart HTTP fallback upload',
        name: 'PhotoUploadService',
      );

      final uploadUrl = Uri.parse(
        'https://api.gallevr.app/vrchat/photo/upload?user=${Uri.encodeComponent(authData.userId)}&type=webp',
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
          final galleryUrl = response.body.trim();
          return await _handleUploadSuccess(
            galleryUrl,
            photoMetadata,
            photoPath,
            originalPath,
            config,
          );
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
    } finally {
      if (deleteFileOnComplete) {
        try {
          final file = File(photoPath);
          if (await file.exists()) {
            await file.delete();
            developer.log(
              'Deleted temporary file: $photoPath',
              name: 'PhotoUploadService',
            );
          }
        } catch (e) {
          developer.log(
            'Error deleting temporary file: $e',
            name: 'PhotoUploadService',
          );
        }
      }
    }
  }

  Future<bool> _handleUploadSuccess(
    String galleryUrl,
    PhotoMetadata photoMetadata,
    String photoPath,
    String? originalPath,
    ConfigModel config,
  ) async {
    developer.log('Photo uploaded successfully', name: 'PhotoUploadService');
    PhotoEventService().notifyError(
      'success',
      'Photo uploaded successfully',
      photoPath: photoPath,
    );

    final updatedMetadata = photoMetadata.copyWith(galleryUrl: galleryUrl);

    final saveResult = await _photoMetadataRepository.savePhotoMetadata(
      updatedMetadata,
    );
    developer.log(
      'Updated metadata with gallery URL, save result: $saveResult',
      name: 'PhotoUploadService',
    );

    PhotoEventService().notifyPhotoUploaded(originalPath ?? photoPath);

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
      PhotoEventService().notifyError('warning', warning, photoPath: photoPath);
    }

    await _soundService.playUploadSound(config);
    developer.log('Played upload complete sound', name: 'PhotoUploadService');

    if (config.autoCopyGalleryUrl && galleryUrl.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: galleryUrl));
        developer.log(
          'Copied gallery URL to clipboard: $galleryUrl',
          name: 'PhotoUploadService',
        );
        PhotoEventService().notifyError(
          'info',
          'Gallery URL copied to clipboard',
          photoPath: photoPath,
        );
      } catch (e) {
        developer.log(
          'Error copying gallery URL to clipboard: $e',
          name: 'PhotoUploadService',
          error: e,
        );
      }
    }

    return true;
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

  static bool? _isCurlInstalledCache;

  static Future<bool> checkCurlInstalled() async {
    if (_isCurlInstalledCache != null) return _isCurlInstalledCache!;
    if (!Platform.isWindows && !Platform.isLinux) {
      _isCurlInstalledCache = false;
      return false;
    }
    try {
      final result = await Process.run('curl', ['--version']);
      _isCurlInstalledCache = result.exitCode == 0;
      return _isCurlInstalledCache!;
    } catch (_) {
      _isCurlInstalledCache = false;
      return false;
    }
  }
}
