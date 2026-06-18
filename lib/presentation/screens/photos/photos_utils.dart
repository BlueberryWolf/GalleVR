import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import '../../theme/app_theme.dart';

String shortenGalleryUrl(String url) {
  try {
    final uri = Uri.parse(url);
    // case 1: https://gallevr.app/p?i=PHOTO_ID&u=...
    if (uri.path == '/p' && uri.queryParameters.containsKey('i')) {
      final photoId = uri.queryParameters['i']!;
      return 'https://gallevr.app/p/$photoId';
    }
    // case 2: https://gallevr.app/gallery/USER_ID?focus=PHOTO_ID
    if (uri.path.startsWith('/gallery/') && uri.queryParameters.containsKey('focus')) {
      final photoId = uri.queryParameters['focus']!;
      return 'https://gallevr.app/p/$photoId';
    }
    // case 3: https://gallevr.app/u/USER_ID?focus=PHOTO_ID
    if (uri.path.startsWith('/u/') && uri.queryParameters.containsKey('focus')) {
      final photoId = uri.queryParameters['focus']!;
      return 'https://gallevr.app/p/$photoId';
    }
  } catch (e) {
    // original url
  }
  return url;
}

/// Utility function to copy text to clipboard and show a snackbar
Future<void> copyToClipboard({
  required String text,
  required BuildContext context,
  required String successMessage,
  String? fallbackText,
  String? fallbackMessage,
  String loggerName = 'ClipboardUtil',
  VoidCallback? onSuccess,
}) async {
  final bool isContextMounted = context.mounted;
  final processedText = shortenGalleryUrl(text);
  final processedFallback = fallbackText != null ? shortenGalleryUrl(fallbackText) : null;

  try {
    await Clipboard.setData(ClipboardData(text: processedText));

    if (isContextMounted && context.mounted) {
      final snackBar = SnackBar(
        content: Text(successMessage),
        action:
            onSuccess != null
                ? SnackBarAction(label: 'Open', onPressed: onSuccess)
                : null,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }

  } catch (e) {
    if (processedFallback != null) {
      try {
        await Clipboard.setData(ClipboardData(text: processedFallback));

        if (isContextMounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fallbackMessage ?? 'Fallback text copied to clipboard',
              ),
            ),
          );
        }
      } catch (e) {
        _handleClipboardError(e, isContextMounted ? context : null, loggerName);
      }
    } else {
      _handleClipboardError(e, isContextMounted ? context : null, loggerName);
    }
  }
}

/// Helper function to handle clipboard errors
void _handleClipboardError(
  dynamic error,
  BuildContext? context,
  String loggerName,
) {
  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error copying to clipboard: $error')),
    );
  }

  developer.log(
    'Error copying to clipboard: $error',
    name: loggerName,
    error: error,
  );
}

/// Shows a modal bottom sheet with consistent styling
void showStyledBottomSheet({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// Utility function to open a URL in the default browser
Future<void> openUrl(
  String url,
  BuildContext context, {
  String loggerName = 'UrlOpener',
}) async {
  try {
    final processedUrl = shortenGalleryUrl(url);
    final uri = Uri.parse(processedUrl);
    bool launched = false;

    if (Platform.isLinux) {
      try {
        if (File('/.flatpak-info').existsSync()) {
          final res = await Process.run(
            'flatpak-spawn',
            ['--host', 'xdg-open', processedUrl],
          );
          launched = res.exitCode == 0;
        } else {
          final env = Map<String, String>.from(Platform.environment);
          env.remove('LD_LIBRARY_PATH');
          env.remove('LD_PRELOAD');
          final res = await Process.run(
            'xdg-open',
            [processedUrl],
            environment: env,
          );
          launched = res.exitCode == 0;
        }
      } catch (e) {
        developer.log('Linux custom launcher failed: $e', name: loggerName);
      }
    }

    if (!launched) {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    if (!launched) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open URL')));
    }
  } catch (e) {
    if (Platform.isLinux) {
      try {
        final env = Map<String, String>.from(Platform.environment);
        env.remove('LD_LIBRARY_PATH');
        env.remove('LD_PRELOAD');
        await Process.run('xdg-open', [url], environment: env);
        return;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening URL: $e')));
    }
    developer.log('Error opening URL: $e', name: loggerName, error: e);
  }
}

/// Utility function to show a file in the system's file explorer
Future<void> showFileInExplorer(String filePath, BuildContext context) async {
  try {
    final uri = Uri.parse('file:${filePath.replaceAll('\\', '/')}');

    if (Platform.isWindows) {
      await Process.run('explorer.exe', [
        '/select,$filePath',
      ], runInShell: true);
      developer.log('Opened file explorer and selected file: $filePath', name: 'FileExplorerUtil');
    } else if (await canLaunchUrl(uri)) {
      final directoryPath = path.dirname(filePath);
      await launchUrl(Uri.parse('file:$directoryPath'));
      developer.log('Opened file explorer at: $directoryPath', name: 'FileExplorerUtil');
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open file explorer')));
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening file explorer: $e')));
    }
    developer.log('Error opening file explorer: $e', name: 'FileExplorerUtil', error: e);
  }
}
