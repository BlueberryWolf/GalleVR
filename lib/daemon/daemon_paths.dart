import 'dart:io';
import 'package:path/path.dart' as path;

class DaemonPaths {
  DaemonPaths._();

  static String get exeDir => path.dirname(Platform.resolvedExecutable);

  static String getAppSupportDir() {
    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          path.join(Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Roaming');
      final dir = path.join(appData, 'com.gallevr', 'GalleVR');
      Directory(dir).createSync(recursive: true);
      return dir;
    } else {
      final dataHome =
          Platform.environment['XDG_DATA_HOME'] ??
          path.join(Platform.environment['HOME'] ?? '', '.local', 'share');
      final dir = path.join(dataHome, 'com.blueberrywolf.gallevr');
      Directory(dir).createSync(recursive: true);
      return dir;
    }
  }

  static String getConfigDir() {
    if (Platform.isWindows) {
      final dir = path.join(getAppSupportDir(), 'GalleVR');
      Directory(dir).createSync(recursive: true);
      return dir;
    } else {
      final configHome =
          Platform.environment['XDG_CONFIG_HOME'] ??
          path.join(Platform.environment['HOME'] ?? '', '.config');
      final dir = path.join(configHome, 'GalleVR');
      Directory(dir).createSync(recursive: true);
      return dir;
    }
  }

  static String getConfigFilePath() => path.join(getConfigDir(), 'config.json');

  static String getDbPath() => path.join(getAppSupportDir(), 'gallevr.db');

  static String getSharedPrefsPath() =>
      path.join(getAppSupportDir(), 'shared_preferences.json');

  static String getDaemonInfoPath() =>
      path.join(getAppSupportDir(), 'daemon.json');

  static String getDaemonLockPath() =>
      path.join(getAppSupportDir(), 'daemon.lock');

  static String getUiExePath() {
    final name = Platform.isWindows ? 'GalleVR.exe' : 'GalleVR';
    return path.join(exeDir, name);
  }

  static String getDaemonExePath() {
    final name = Platform.isWindows ? 'gallevr_daemon.exe' : 'gallevr_daemon';
    return path.join(exeDir, name);
  }

  static String getAssetPath(String relativeAsset) {
    final normalized = relativeAsset.replaceAll('/', Platform.pathSeparator);
    final candidates = [
      path.join(exeDir, 'data', 'flutter_assets', 'assets', normalized),
      path.join(Directory.current.path, 'assets', normalized),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return candidates.first;
  }

  static String? getCwebpPath() {
    final filename = Platform.isWindows ? 'cwebp.exe' : 'cwebp';
    final platformDir = Platform.isWindows ? 'windows' : 'linux';
    final candidates = [
      path.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'bin',
        platformDir,
        filename,
      ),
      path.join(getAppSupportDir(), 'cwebp', filename),
      path.join(Directory.current.path, 'assets', 'bin', platformDir, filename),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static String getTempUploadDir() {
    final dateStr = DateTime.now().toIso8601String().split('T')[0];
    final dir = path.join(Directory.systemTemp.path, 'GalleVR-Temp', dateStr);
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  static String getDefaultPhotosDir() {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      return home.isEmpty ? '' : path.join(home, 'Pictures', 'VRChat');
    }
    return '';
  }

  static String getDefaultResoniteDir() {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      return home.isEmpty ? '' : path.join(home, 'Pictures', 'Resonite');
    }
    final home = Platform.environment['HOME'] ?? '';
    return home.isEmpty ? '' : path.join(home, 'Pictures', 'Resonite');
  }

  static String getDefaultLogsDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      if (appData.isEmpty) return '';
      return path.join(path.dirname(appData), 'LocalLow', 'VRChat', 'VRChat');
    }
    return '';
  }
}
