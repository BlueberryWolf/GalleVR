import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

/// Consolidated utility functions for screenshots
class ScreenshotUtils {
  // VRChat screenshot filename regex
  // Pattern: VRChat_YYYY-MM-DD_HH-MM-SS.mmm_WIDTHxHEIGHT.png
  static final RegExp vrchatScreenshotPattern = RegExp(
    r'^VRChat_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}_\d+x\d+\.png$',
  );

  static bool isVRChatScreenshot(String filePath) {
    final filename = path.basename(filePath);
    return vrchatScreenshotPattern.hasMatch(filename);
  }

  static String translatePlatformPath(String inputPath, String configPhotosDirectory) {
    if ((Platform.isLinux || Platform.isMacOS) && inputPath.contains(r'\')) {
      final photosDirName = path.basename(configPhotosDirectory);
      const pathSeparator = r'\';

      final vrchatFolderIndex = inputPath.toLowerCase().lastIndexOf(
        photosDirName.toLowerCase() + pathSeparator,
      );

      if (vrchatFolderIndex != -1) {
        final relativePath = inputPath.substring(
          vrchatFolderIndex + photosDirName.length + 1,
        );
        final platformRelativePath = relativePath.replaceAll(
          r'\',
          path.separator,
        );

        return path.join(configPhotosDirectory, platformRelativePath);
      }
    }
    return inputPath;
  }

  static Future<bool> waitForFileReady(
    File file, {
    int maxAttempts = 25,
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    int lastSize = -1;
    for (int i = 0; i < maxAttempts; i++) {
      if (await file.exists()) {
        try {
          final length = await file.length();
          if (length > 0 && length == lastSize) {
            return true;
          }
          lastSize = length;
        } catch (_) {
          // File might be locked or not fully created
        }
      }
      await Future.delayed(interval);
    }

    try {
      if (await file.exists() && (await file.length()) > 0) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}
