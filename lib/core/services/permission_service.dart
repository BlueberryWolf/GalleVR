import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:developer' as developer;

class PermissionService {
  Future<bool> checkStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 33) {
          // For Android 13+, check granular media permissions
          final photos = await Permission.photos.status;
          final videos = await Permission.videos.status;

          // We need both photos and videos permissions for the app to function properly
          return photos.isGranted && videos.isGranted;
        } else if (sdkInt >= 30) {
          // For Android 11-12, we need storage permission
          final storage = await Permission.storage.status;
          return storage.isGranted;
        } else {
          // For Android 10 and below
          final storage = await Permission.storage.status;
          return storage.isGranted;
        }
      } else {
        // Non-Android platforms don't need these permissions
        return true;
      }
    } catch (e) {
      developer.log(
        'Error checking permissions: $e',
        name: 'PermissionService',
      );
      return false;
    }
  }

  Future<bool> requestStoragePermissionsOnStartup() async {
    try {
      if (Platform.isAndroid) {
        developer.log(
          'Requesting Android storage permissions on startup',
          name: 'PermissionService',
        );

        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        developer.log(
          'Android SDK version: $sdkInt',
          name: 'PermissionService',
        );

        if (sdkInt >= 33) {
          developer.log(
            'Requesting media permissions for Android 13+',
            name: 'PermissionService',
          );

          final photos = await Permission.photos.request();
          final videos = await Permission.videos.request();

          // Also request documents permission if available
          // Note: permission_handler doesn't have a direct READ_MEDIA_DOCUMENTS permission
          // so we're using what's available for documents access

          developer.log(
            'Media permissions results - Photos: $photos, Videos: $videos',
            name: 'PermissionService',
          );

          // We need both photos and videos permissions for the app to function properly
          return photos.isGranted && videos.isGranted;
        } else if (sdkInt >= 30) {
          developer.log(
            'Requesting storage permissions for Android 11-12',
            name: 'PermissionService',
          );

          final storageResult = await Permission.storage.request();
          developer.log(
            'Storage permission result: $storageResult',
            name: 'PermissionService',
          );

          return storageResult.isGranted;
        } else {
          developer.log(
            'Requesting storage permissions for Android 10 and below',
            name: 'PermissionService',
          );

          final result = await Permission.storage.request();
          developer.log(
            'Storage permission result: $result',
            name: 'PermissionService',
          );

          return result.isGranted;
        }
      } else {
        return true;
      }
    } catch (e) {
      developer.log(
        'Error requesting permissions: $e',
        name: 'PermissionService',
      );
      return false;
    }
  }

  Future<bool> requestStoragePermissions(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        developer.log(
          'Requesting Android storage permissions',
          name: 'PermissionService',
        );

        final hasPermissions = await checkStoragePermissions();
        if (hasPermissions) {
          developer.log(
            'Storage permissions already granted',
            name: 'PermissionService',
          );
          return true;
        }

        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        developer.log(
          'Android SDK version: $sdkInt',
          name: 'PermissionService',
        );

        if (sdkInt >= 33) {
          developer.log(
            'Requesting media permissions for Android 13+',
            name: 'PermissionService',
          );

          final photos = await Permission.photos.request();
          final videos = await Permission.videos.request();

          // Also request documents permission if available
          // Note: permission_handler doesn't have a direct READ_MEDIA_DOCUMENTS permission
          // so we're using what's available for documents access

          developer.log(
            'Media permissions results - Photos: $photos, Videos: $videos',
            name: 'PermissionService',
          );

          // Check if any permissions were permanently denied
          if (photos.isPermanentlyDenied || videos.isPermanentlyDenied) {
            if (context.mounted) {
              final shouldOpenSettings = await _showPermissionDialog(
                context,
                'Media Permissions Required',
                'GalleVR needs access to your photos and videos to work with VRChat content. Please grant these permissions in the settings.',
              );

              if (shouldOpenSettings) {
                await openAppSettings();
              }
            }
          }

          return photos.isGranted && videos.isGranted;
        } else if (sdkInt >= 30) {
          developer.log(
            'Requesting storage permissions for Android 11-12',
            name: 'PermissionService',
          );

          final storageResult = await Permission.storage.request();
          developer.log(
            'Storage permission result: $storageResult',
            name: 'PermissionService',
          );

          if (storageResult.isPermanentlyDenied) {
            if (context.mounted) {
              final shouldOpenSettings = await _showPermissionDialog(
                context,
                'Storage Permission Required',
                'GalleVR needs storage access to work with VRChat photos. Please grant storage permissions in the settings.',
              );

              if (shouldOpenSettings) {
                await openAppSettings();
              }
            }
          }

          return storageResult.isGranted;
        } else {
          developer.log(
            'Requesting storage permissions for Android 10 and below',
            name: 'PermissionService',
          );

          final result = await Permission.storage.request();
          developer.log(
            'Storage permission result: $result',
            name: 'PermissionService',
          );

          if (result.isPermanentlyDenied) {
            if (context.mounted) {
              final shouldOpenSettings = await _showPermissionDialog(
                context,
                'Storage Permission Required',
                'GalleVR needs storage access to work with VRChat photos. Please grant storage permissions in the settings.',
              );

              if (shouldOpenSettings) {
                await openAppSettings();
              }
            }
          }

          return result.isGranted;
        }
      } else {
        return true;
      }
    } catch (e) {
      developer.log(
        'Error requesting permissions: $e',
        name: 'PermissionService',
      );
      return false;
    }
  }

  Future<bool> _showPermissionDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
    );

    return result ?? false;
  }
}
