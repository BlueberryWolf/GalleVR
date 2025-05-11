import 'dart:io';

import 'platform_service.dart';
import 'windows_platform_service.dart';
import 'android_platform_service.dart';

// Factory class to create the appropriate PlatformService based on the current platform
class PlatformServiceFactory {
  // Get the appropriate PlatformService for the current platform
  static PlatformService getPlatformService() {
    if (Platform.isWindows) {
      return WindowsPlatformService();
    } else if (Platform.isAndroid) {
      return AndroidPlatformService();
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }
}
