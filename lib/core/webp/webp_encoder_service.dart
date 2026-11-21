import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../image/image_dimensions_reader.dart';

class WebpEncoderService {
  static const int maxSizeKb = 150;
  static const int maxAttempts = 5;

  Future<String> _getCwebpPath() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cwebpDir = Directory(path.join(appDir.path, 'cwebp'));
      final cwebpFilename = Platform.isLinux ? 'cwebp' : 'cwebp.exe';
      final cwebpPath = path.join(cwebpDir.path, cwebpFilename);

      if (!await File(cwebpPath).exists()) {
        if (!await cwebpDir.exists()) {
          await cwebpDir.create(recursive: true);
        }

        final assetPath =
            Platform.isLinux
                ? 'assets/bin/linux/cwebp'
                : 'assets/bin/windows/cwebp.exe';

        final byteData = await rootBundle.load(assetPath);
        final buffer = byteData.buffer;
        final bytes = buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );

        await File(cwebpPath).writeAsBytes(bytes);

        if (Platform.isLinux) {
          try {
            await Process.run('chmod', ['+x', cwebpPath]);
          } catch (chmodError) {
            developer.log(
              'Error making cwebp executable: $chmodError',
              name: 'WebpEncoderService',
            );
          }
        }
      }

      return cwebpPath;
    } catch (e) {
      developer.log(
        'Error extracting cwebp binary: $e',
        name: 'WebpEncoderService',
      );
      throw Exception('Failed to extract cwebp binary: $e');
    }
  }

  Future<void> encodeFileToWebP(
    String inputPath,
    String outputPath, {
    required int quality,
    int? targetWidth,
    int? targetHeight,
    int? maxSizeBytes,
    int? originalWidth,
    int? originalHeight,
  }) async {
    if (Platform.isAndroid) {
      int currentQuality = quality;
      int attempts = 0;
      const maxAttempts = 5;

      int width = originalWidth ?? 0;
      int height = originalHeight ?? 0;

      if (width <= 0 || height <= 0) {
        final dims = await ImageDimensionsReader.readFromFile(inputPath);
        if (dims != null) {
          width = dims.width;
          height = dims.height;
        }
      }

      final int finalMinWidth = targetWidth ?? (width > 0 ? width : 1920);
      final int finalMinHeight = targetHeight ?? (height > 0 ? height : 1080);

      while (attempts < maxAttempts) {
        final result = await FlutterImageCompress.compressAndGetFile(
          inputPath,
          outputPath,
          quality: currentQuality,
          minWidth: finalMinWidth,
          minHeight: finalMinHeight,
          format: CompressFormat.webp,
        );

        if (result == null) {
          throw Exception('flutter_image_compress returned null');
        }

        final size = await File(outputPath).length();
        if (maxSizeBytes == null || size <= maxSizeBytes) {
          developer.log(
            'Direct Android FlutterImageCompress encode succeeded: $size bytes (limit was ${maxSizeBytes ?? 'none'}) with quality $currentQuality on attempt ${attempts + 1}',
            name: 'WebpEncoderService',
          );
          return;
        }

        developer.log(
          'Encoded file size $size bytes exceeds limit of $maxSizeBytes bytes on Android. Retrying with lower quality...',
          name: 'WebpEncoderService',
        );

        currentQuality -= 10;
        if (currentQuality < 50) {
          currentQuality = 50;
        }
        attempts++;

        if (currentQuality == 50 && attempts >= maxAttempts) {
          break;
        }
      }
      return;
    }

    final cwebpPath = await _getCwebpPath();

    int currentQuality = quality;
    int attempts = 0;
    const maxAttempts = 5;

    while (attempts < maxAttempts) {
      final args = ['-m', '4', '-q', currentQuality.toString()];

      if (targetWidth != null && targetHeight != null) {
        args.addAll([
          '-resize',
          targetWidth.toString(),
          targetHeight.toString(),
        ]);
      }

      args.addAll(['-o', outputPath, inputPath]);

      final result = await Process.run(cwebpPath, args);
      if (result.exitCode != 0) {
        throw Exception('cwebp failed: ${result.stderr}');
      }

      final size = await File(outputPath).length();
      if (maxSizeBytes == null || size <= maxSizeBytes) {
        developer.log(
          'Direct cwebp encode succeeded: $size bytes (limit was ${maxSizeBytes ?? 'none'}) with quality $currentQuality on attempt ${attempts + 1}',
          name: 'WebpEncoderService',
        );
        return;
      }

      developer.log(
        'Encoded file size $size bytes exceeds limit of $maxSizeBytes bytes. Retrying with lower quality...',
        name: 'WebpEncoderService',
      );

      currentQuality -= 10;
      if (currentQuality < 50) {
        currentQuality = 50;
      }
      attempts++;

      if (currentQuality == 50 && attempts >= maxAttempts) {
        break;
      }
    }
  }
}
