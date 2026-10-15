import 'dart:io';
import 'dart:developer' as developer;

import 'package:win32_registry/win32_registry.dart';
import 'package:process_run/process_run.dart';

class VRChatRegistryService {
  static const String vrchatRegistryPath = r'Software\VRChat\VRChat';

  Future<bool> isVRChatRunning() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Checking if VRChat is running',
        name: 'VRChatRegistryService',
      );

      final shell = Shell();
      final result = await shell.run(
        'tasklist /FI "IMAGENAME eq VRChat.exe" /NH',
      );

      final output = result.outText;
      final isRunning = output.contains('VRChat.exe');

      developer.log(
        'VRChat running status: $isRunning',
        name: 'VRChatRegistryService',
      );

      return isRunning;
    } catch (e) {
      developer.log(
        'Error checking if VRChat is running: $e',
        name: 'VRChatRegistryService',
      );
      return false;
    }
  }

  Future<bool> doesVRChatRegistryKeyExist() async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: vrchatRegistryPath,
      );
      final exists = key.hkey != 0;
      key.close();
      return exists;
    } catch (e) {
      developer.log(
        'Error checking VRChat registry key: $e',
        name: 'VRChatRegistryService',
      );
      return false;
    }
  }

  /// Whether any `LOGGING_ENABLED` key is set to 1.
  Future<bool> isFullLoggingEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Checking if VRChat registry key exists',
        name: 'VRChatRegistryService',
      );

      final keyExists = await doesVRChatRegistryKeyExist();

      if (!keyExists) {
        developer.log(
          'VRChat registry key does not exist',
          name: 'VRChatRegistryService',
        );
        return false;
      }

      developer.log(
        'Opening VRChat registry key',
        name: 'VRChatRegistryService',
      );

      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: vrchatRegistryPath,
      );

      bool foundLoggingKey = false;
      bool isEnabled = false;

      developer.log('Checking registry values', name: 'VRChatRegistryService');

      for (final value in key.values) {
        developer.log(
          'Found registry value: ${value.name}',
          name: 'VRChatRegistryService',
        );

        if (value.name.startsWith('LOGGING_ENABLED')) {
          foundLoggingKey = true;

          developer.log(
            'Found logging key: ${value.name}, type: ${value.runtimeType}',
            name: 'VRChatRegistryService',
          );

          if (value is Int32Value) {
            isEnabled = value.value == 1;
            developer.log(
              'Logging value: ${value.value}, enabled: $isEnabled',
              name: 'VRChatRegistryService',
            );
            if (isEnabled) break;
          }
        }
      }

      key.close();

      developer.log(
        'VRChat logging status - foundKey: $foundLoggingKey, isEnabled: $isEnabled',
        name: 'VRChatRegistryService',
      );

      return foundLoggingKey && isEnabled;
    } catch (e) {
      developer.log(
        'Error checking VRChat logging status: $e',
        name: 'VRChatRegistryService',
      );
      return false;
    }
  }

  /// Turns on VRChat full logging in the registry. Returns false on failure.
  Future<bool> enableFullLogging() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Attempting to enable VRChat full logging',
        name: 'VRChatRegistryService',
      );

      try {
        final key = Registry.openPath(
          RegistryHive.currentUser,
          path: vrchatRegistryPath,
          desiredAccessRights: AccessRights.allAccess,
        );

        String? existingLoggingKeyName;

        developer.log(
          'Looking for existing LOGGING_ENABLED keys',
          name: 'VRChatRegistryService',
        );

        for (final value in key.values) {
          developer.log(
            'Found registry value: ${value.name}',
            name: 'VRChatRegistryService',
          );

          if (value.name.startsWith('LOGGING_ENABLED')) {
            existingLoggingKeyName = value.name;
            developer.log(
              'Found existing logging key: $existingLoggingKeyName',
              name: 'VRChatRegistryService',
            );
            break;
          }
        }

        if (existingLoggingKeyName != null) {
          developer.log(
            'Setting existing key $existingLoggingKeyName to 1',
            name: 'VRChatRegistryService',
          );
          key.createValue(RegistryValue.int32(existingLoggingKeyName, 1));
        } else {
          // VRChat reads this exact hashed key name.
          const newKeyName = 'LOGGING_ENABLED_h120798204';
          developer.log(
            'No existing logging key found, creating $newKeyName',
            name: 'VRChatRegistryService',
          );
          key.createValue(RegistryValue.int32(newKeyName, 1));
        }

        key.close();

        developer.log(
          'Successfully enabled VRChat full logging',
          name: 'VRChatRegistryService',
        );
        return true;
      } catch (e) {
        developer.log(
          'Error opening VRChat registry key: $e',
          name: 'VRChatRegistryService',
        );

        try {
          final softwareKey = Registry.openPath(
            RegistryHive.currentUser,
            path: 'Software',
            desiredAccessRights: AccessRights.allAccess,
          );

          final vrchatKey = softwareKey.createKey('VRChat');

          final vrchatSubKey = vrchatKey.createKey('VRChat');

          const loggingKeyName = 'LOGGING_ENABLED_h120798204';
          developer.log(
            'Creating new logging key: $loggingKeyName',
            name: 'VRChatRegistryService',
          );
          vrchatSubKey.createValue(RegistryValue.int32(loggingKeyName, 1));

          vrchatSubKey.close();
          vrchatKey.close();
          softwareKey.close();

          developer.log(
            'Successfully created VRChat registry key and enabled logging',
            name: 'VRChatRegistryService',
          );
          return true;
        } catch (createError) {
          developer.log(
            'Error creating VRChat registry key: $createError',
            name: 'VRChatRegistryService',
          );
          return false;
        }
      }
    } catch (e) {
      developer.log(
        'Error enabling VRChat full logging: $e',
        name: 'VRChatRegistryService',
      );
      return false;
    }
  }
}
