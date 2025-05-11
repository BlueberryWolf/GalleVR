import 'dart:io';
import 'dart:developer' as developer;

import 'package:win32_registry/win32_registry.dart';
import 'package:process_run/process_run.dart';

/// Service for managing VRChat-related registry settings
class VRChatRegistryService {
  /// The registry path for VRChat settings
  static const String vrchatRegistryPath = r'Software\VRChat\VRChat';

  /// Checks if VRChat is currently running
  Future<bool> isVRChatRunning() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Checking if VRChat is running',
        name: 'VRChatRegistryService',
      );

      // Use tasklist to check if VRChat.exe is running
      final shell = Shell();
      final result = await shell.run('tasklist /FI "IMAGENAME eq VRChat.exe" /NH');

      // Check if VRChat.exe is in the output
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

  /// Checks if the VRChat registry key exists
  Future<bool> doesVRChatRegistryKeyExist() async {
    if (!Platform.isWindows) return false;

    try {
      final key = Registry.openPath(RegistryHive.currentUser,
          path: vrchatRegistryPath);
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

  /// Checks if full logging is enabled in VRChat
  ///
  /// Returns true if any LOGGING_ENABLED key is set to hexadecimal 1
  Future<bool> isFullLoggingEnabled() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Checking if VRChat registry key exists',
        name: 'VRChatRegistryService',
      );

      // First check if the key exists
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

      final key = Registry.openPath(RegistryHive.currentUser,
          path: vrchatRegistryPath);

      // Check for any LOGGING_ENABLED key
      bool foundLoggingKey = false;
      bool isEnabled = false;

      developer.log(
        'Checking registry values',
        name: 'VRChatRegistryService',
      );

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

          // Check if the value is set to hexadecimal 1
          if (value is Int32Value) {
            isEnabled = value.value == 1;
            developer.log(
              'Logging value: ${value.value}, enabled: $isEnabled',
              name: 'VRChatRegistryService',
            );
            if (isEnabled) break; // If we find one that's enabled, we're done
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

  /// Enables full logging in VRChat by setting the registry key
  ///
  /// Returns true if successful
  Future<bool> enableFullLogging() async {
    if (!Platform.isWindows) return false;

    try {
      developer.log(
        'Attempting to enable VRChat full logging',
        name: 'VRChatRegistryService',
      );

      // Open the VRChat registry key with write access
      try {
        // Try to open the key with write access
        final key = Registry.openPath(
          RegistryHive.currentUser,
          path: vrchatRegistryPath,
          desiredAccessRights: AccessRights.allAccess,
        );

        // Find any existing LOGGING_ENABLED keys
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

        // Set the logging key to hexadecimal 1
        if (existingLoggingKeyName != null) {
          developer.log(
            'Setting existing key $existingLoggingKeyName to 1',
            name: 'VRChatRegistryService',
          );
          key.createValue(RegistryValue.int32(existingLoggingKeyName, 1));
        } else {
          // If no existing key found, create a new one with the specific hash suffix
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
        // If the key doesn't exist, create it
        developer.log(
          'Error opening VRChat registry key: $e',
          name: 'VRChatRegistryService',
        );

        try {
          // Create the parent keys if needed
          final softwareKey = Registry.openPath(
            RegistryHive.currentUser,
            path: 'Software',
            desiredAccessRights: AccessRights.allAccess,
          );

          // Create the VRChat key
          final vrchatKey = softwareKey.createKey('VRChat');

          // Create the VRChat subkey
          final vrchatSubKey = vrchatKey.createKey('VRChat');

          // Create the logging key
          const loggingKeyName = 'LOGGING_ENABLED_h120798204';
          developer.log(
            'Creating new logging key: $loggingKeyName',
            name: 'VRChatRegistryService',
          );
          vrchatSubKey.createValue(RegistryValue.int32(loggingKeyName, 1));

          // Clean up
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
