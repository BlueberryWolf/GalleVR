import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<void> sanitizeSharedPreferencesFile() async {
  if (!Platform.isWindows && !Platform.isLinux) return;

  try {
    final supportDir = await getApplicationSupportDirectory();
    final prefsPath = path.join(supportDir.path, 'shared_preferences.json');
    final prefsFile = File(prefsPath);

    if (!await prefsFile.exists()) return;

    try {
      final raw = await prefsFile.readAsString();
      if (raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is Map) {
        final sanitized = <String, Object>{};
        var needsRewrite = false;
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value != null) {
            sanitized[entry.key as String] = entry.value as Object;
          } else {
            needsRewrite = true;
          }
        }
        if (!needsRewrite) return;

        final tmpFile = File('$prefsPath.tmp');
        await tmpFile.writeAsString(json.encode(sanitized), flush: true);
        try {
          await tmpFile.rename(prefsPath);
        } catch (_) {
          await prefsFile.writeAsString(json.encode(sanitized), flush: true);
          if (await tmpFile.exists()) {
            await tmpFile.delete().catchError((_) => tmpFile);
          }
        }
        developer.log(
          'Sanitized invalid entries in shared_preferences.json',
          name: 'PrefsSanitizer',
        );
        return;
      }
    } catch (e) {
      developer.log(
        'Corrupted shared_preferences.json detected: $e',
        name: 'PrefsSanitizer',
      );
    }

    final backupFile = File('$prefsPath.corrupt');
    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await prefsFile.copy(backupFile.path);
    } catch (_) {}

    try {
      await prefsFile.delete();
    } catch (_) {
      await prefsFile.writeAsString('{}', flush: true);
    }

    developer.log(
      'Reset corrupted shared_preferences.json',
      name: 'PrefsSanitizer',
    );
  } catch (e) {
    developer.log(
      'Failed to check shared_preferences.json: $e',
      name: 'PrefsSanitizer',
    );
  }
}
