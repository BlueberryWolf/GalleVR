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
          await Permission.photos.status;
          await Permission.videos.status;
          await Permission.audio.status;
          final manageStorage = await Permission.manageExternalStorage.status;

          return manageStorage.isGranted;
        } else if (sdkInt >= 30) {
          final manageStorage = await Permission.manageExternalStorage.status;
          return manageStorage.isGranted;
        } else if (sdkInt == 29) {
          final storage = await Permission.storage.status;
          return storage.isGranted;
        } else {
          final storage = await Permission.storage.status;
          return storage.isGranted;
        }
      } else {
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
          final audio = await Permission.audio.request();

          developer.log(
            'Media permissions results - Photos: $photos, Videos: $videos, Audio: $audio',
            name: 'PermissionService',
          );

          final manageResult = await Permission.manageExternalStorage.request();
          developer.log(
            'MANAGE_EXTERNAL_STORAGE permission result: $manageResult',
            name: 'PermissionService',
          );

          return manageResult.isGranted;
        } else if (sdkInt >= 30) {
          developer.log(
            'Requesting MANAGE_EXTERNAL_STORAGE for Android 11-12',
            name: 'PermissionService',
          );

          final manageResult = await Permission.manageExternalStorage.request();
          developer.log(
            'MANAGE_EXTERNAL_STORAGE permission result: $manageResult',
            name: 'PermissionService',
          );

          return manageResult.isGranted;
        } else if (sdkInt == 29) {
          developer.log(
            'Requesting storage permissions for Android 10',
            name: 'PermissionService',
          );

          final readResult = await Permission.storage.request();
          developer.log(
            'Storage permission result: $readResult',
            name: 'PermissionService',
          );

          developer.log(
            'Using requestLegacyExternalStorage for Android 10 compatibility',
            name: 'PermissionService',
          );

          return readResult.isGranted;
        } else {
          developer.log(
            'Requesting storage permissions for Android 9 and below',
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
          final audio = await Permission.audio.request();

          developer.log(
            'Media permissions results - Photos: $photos, Videos: $videos, Audio: $audio',
            name: 'PermissionService',
          );

          final manageResult = await Permission.manageExternalStorage.request();
          developer.log(
            'MANAGE_EXTERNAL_STORAGE permission result: $manageResult',
            name: 'PermissionService',
          );

          if (manageResult.isPermanentlyDenied) {
            if (context.mounted) {
              final shouldOpenSettings = await _showPermissionDialog(
                context,
                'Storage Permission Required',
                'GalleVR needs full storage access to work with VRChat photos. Please grant "All files access" in the settings.',
              );

              if (shouldOpenSettings) {
                await openAppSettings();
              }
            }
          }

          return manageResult.isGranted;
        } else if (sdkInt >= 30) {
          developer.log(
            'Requesting MANAGE_EXTERNAL_STORAGE for Android 11-12',
            name: 'PermissionService',
          );

          final manageResult = await Permission.manageExternalStorage.request();
          developer.log(
            'MANAGE_EXTERNAL_STORAGE permission result: $manageResult',
            name: 'PermissionService',
          );

          if (manageResult.isPermanentlyDenied) {
            if (context.mounted) {
              final shouldOpenSettings = await _showPermissionDialog(
                context,
                'Storage Permission Required',
                'GalleVR needs full storage access to work with VRChat photos. Please grant "All files access" in the settings.',
              );

              if (shouldOpenSettings) {
                await openAppSettings();
              }
            }
          }

          return manageResult.isGranted;
        } else if (sdkInt == 29) {
          developer.log(
            'Requesting storage permissions for Android 10',
            name: 'PermissionService',
          );

          final readResult = await Permission.storage.request();
          developer.log(
            'Storage permission result: $readResult',
            name: 'PermissionService',
          );

          developer.log(
            'Using requestLegacyExternalStorage for Android 10 compatibility',
            name: 'PermissionService',
          );

          if (readResult.isPermanentlyDenied) {
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

          return readResult.isGranted;
        } else {
          developer.log(
            'Requesting storage permissions for Android 9 and below',
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
