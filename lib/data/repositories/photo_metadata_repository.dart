import 'dart:convert';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/photo_metadata.dart';
import '../services/vrcx_metadata_service.dart';

class PhotoMetadataRepository {
  static const String _photoIdsKey = 'gallevr_photo_ids';
  static const String _photoMetadataKeyPrefix = 'gallevr_photo_';

  Future<bool> savePhotoMetadata(PhotoMetadata metadata) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final photoId = '${metadata.filename}_${metadata.takenDate}';

      developer.log(
        'Saving metadata for photo ID: $photoId',
        name: 'PhotoMetadataRepository',
      );
      developer.log(
        'Metadata details: Filename: ${metadata.filename}, Path: ${metadata.localPath}',
        name: 'PhotoMetadataRepository',
      );
      developer.log(
        'World: ${metadata.world?.name}, Players: ${metadata.players.length}',
        name: 'PhotoMetadataRepository',
      );
      if (metadata.galleryUrl != null) {
        developer.log(
          'Gallery URL: ${metadata.galleryUrl}',
          name: 'PhotoMetadataRepository',
        );
      }

      final existingMetadata = await getPhotoMetadataForFile(
        metadata.localPath ?? metadata.filename,
      );
      if (existingMetadata != null) {
        final existingPhotoId =
            '${existingMetadata.filename}_${existingMetadata.takenDate}';
        developer.log(
          'Updating existing metadata with ID: $existingPhotoId',
          name: 'PhotoMetadataRepository',
        );

        final updatedMetadata = existingMetadata.copyWith(
          world: metadata.world ?? existingMetadata.world,
          players:
              metadata.players.isNotEmpty
                  ? metadata.players
                  : existingMetadata.players,
          galleryUrl: metadata.galleryUrl ?? existingMetadata.galleryUrl,
        );

        final metadataJson = json.encode(updatedMetadata.toJson());
        await prefs.setString(
          '$_photoMetadataKeyPrefix$existingPhotoId',
          metadataJson,
        );

        final savedMetadata = prefs.getString(
          '$_photoMetadataKeyPrefix$existingPhotoId',
        );
        if (savedMetadata != null) {
          developer.log(
            'Existing metadata updated successfully',
            name: 'PhotoMetadataRepository',
          );
          return true;
        } else {
          developer.log(
            'Failed to update existing metadata',
            name: 'PhotoMetadataRepository',
          );
          return false;
        }
      } else {
        final metadataJson = json.encode(metadata.toJson());
        await prefs.setString('$_photoMetadataKeyPrefix$photoId', metadataJson);

        final photoIds = prefs.getStringList(_photoIdsKey) ?? [];
        if (!photoIds.contains(photoId)) {
          photoIds.add(photoId);
          await prefs.setStringList(_photoIdsKey, photoIds);
          developer.log(
            'Added new photo ID to list: $photoId',
            name: 'PhotoMetadataRepository',
          );
        } else {
          developer.log(
            'Photo ID already exists in list: $photoId',
            name: 'PhotoMetadataRepository',
          );
        }

        final savedMetadata = prefs.getString(
          '$_photoMetadataKeyPrefix$photoId',
        );
        if (savedMetadata != null) {
          developer.log(
            'New metadata saved successfully',
            name: 'PhotoMetadataRepository',
          );
          return true;
        } else {
          developer.log(
            'Failed to save new metadata',
            name: 'PhotoMetadataRepository',
          );
          return false;
        }
      }
    } catch (e) {
      developer.log(
        'Error saving photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return false;
    }
  }

  Future<PhotoMetadata?> getPhotoMetadata(String photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = prefs.getString('$_photoMetadataKeyPrefix$photoId');

      if (metadataJson == null) {
        return null;
      }

      return PhotoMetadata.fromJson(json.decode(metadataJson));
    } catch (e) {
      developer.log(
        'Error getting photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return null;
    }
  }

  Future<List<PhotoMetadata>> getAllPhotoMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoIds = prefs.getStringList(_photoIdsKey) ?? [];

      final List<PhotoMetadata> result = [];

      for (final photoId in photoIds) {
        final metadataJson = prefs.getString(
          '$_photoMetadataKeyPrefix$photoId',
        );
        if (metadataJson != null) {
          try {
            final metadata = PhotoMetadata.fromJson(json.decode(metadataJson));
            result.add(metadata);
          } catch (e) {
            developer.log(
              'Error parsing metadata for photo $photoId: $e',
              name: 'PhotoMetadataRepository',
              error: e,
            );
          }
        }
      }

      result.sort((a, b) => b.takenDate.compareTo(a.takenDate));

      return result;
    } catch (e) {
      developer.log(
        'Error getting all photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return [];
    }
  }

  Future<PhotoMetadata?> getPhotoMetadataForFile(String filePath) async {
    try {
      final filename = path.basename(filePath);
      final allMetadata = await getAllPhotoMetadata();

      developer.log(
        'Looking for metadata for file: $filename',
        name: 'PhotoMetadataRepository',
      );
      developer.log(
        'Available metadata count: ${allMetadata.length}',
        name: 'PhotoMetadataRepository',
      );

      if (allMetadata.isNotEmpty) {
        final sampleSize = allMetadata.length > 3 ? 3 : allMetadata.length;
        for (int i = 0; i < sampleSize; i++) {
          final meta = allMetadata[i];
          developer.log(
            'Sample metadata $i: filename=${meta.filename}, path=${meta.localPath}, galleryUrl=${meta.galleryUrl}',
            name: 'PhotoMetadataRepository',
          );
        }
      }

      PhotoMetadata? result;

      result = allMetadata.firstWhere(
        (metadata) => metadata.localPath == filePath,
        orElse: () => PhotoMetadata(takenDate: 0, filename: ''),
      );

      if (result.filename.isNotEmpty) {
        developer.log(
          'Found metadata by exact path match',
          name: 'PhotoMetadataRepository',
        );
        return result;
      }

      result = allMetadata.firstWhere(
        (metadata) => metadata.filename == filename,
        orElse: () => PhotoMetadata(takenDate: 0, filename: ''),
      );

      if (result.filename.isNotEmpty) {
        developer.log(
          'Found metadata by exact filename match',
          name: 'PhotoMetadataRepository',
        );
        return result;
      }

      final filenameWithoutExt = path.basenameWithoutExtension(filePath);
      result = allMetadata.firstWhere(
        (metadata) => metadata.filename.contains(filenameWithoutExt),
        orElse: () => PhotoMetadata(takenDate: 0, filename: ''),
      );

      if (result.filename.isNotEmpty) {
        developer.log(
          'Found metadata by filename contains match',
          name: 'PhotoMetadataRepository',
        );
        return result;
      }

      developer.log(
        'No GalleVR metadata found for $filename, checking for VRCX metadata',
        name: 'PhotoMetadataRepository',
      );

      // Check for VRCX metadata in the image file
      final vrcxService = VrcxMetadataService();
      final vrcxMetadata = await vrcxService.extractVrcxMetadata(filePath);

      if (vrcxMetadata != null) {
        developer.log(
          'Found VRCX metadata for $filename, saving to GalleVR format',
          name: 'PhotoMetadataRepository',
        );

        // Save the converted metadata to GalleVR's storage
        final saveResult = await savePhotoMetadata(vrcxMetadata);

        if (saveResult) {
          developer.log(
            'Successfully saved VRCX metadata for $filename',
            name: 'PhotoMetadataRepository',
          );

          // Successfully processed this file

          // Return the saved metadata
          return vrcxMetadata;
        } else {
          developer.log(
            'Failed to save VRCX metadata for $filename',
            name: 'PhotoMetadataRepository',
          );
        }
      }

      developer.log(
        'No metadata found for $filename',
        name: 'PhotoMetadataRepository',
      );
      return null;
    } catch (e) {
      developer.log(
        'Error getting photo metadata for file: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return null;
    }
  }

  Future<bool> deletePhotoMetadata(String photoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('$_photoMetadataKeyPrefix$photoId');

      final photoIds = prefs.getStringList(_photoIdsKey) ?? [];
      photoIds.remove(photoId);
      await prefs.setStringList(_photoIdsKey, photoIds);

      return true;
    } catch (e) {
      developer.log(
        'Error deleting photo metadata: $e',
        name: 'PhotoMetadataRepository',
        error: e,
      );
      return false;
    }
  }

  /// Resets the VRCX metadata cache
  ///
  /// This allows the app to check for VRCX metadata again for files that have already been checked
  void resetVrcxMetadataCache() {
    developer.log(
      'Clearing VRCX metadata cache',
      name: 'PhotoMetadataRepository',
    );

    // Clear the VRCX service cache
    VrcxMetadataService().clearCache();
  }
}
