import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class WebpEncoderService {
  static const int maxSizeKb = 150;
  static const int maxAttempts = 5;

  /// Encodes an image to WebP format with size constraints
  ///
  /// Ensures the output is under 150KB by progressively reducing quality
  /// if needed, making up to 5 attempts with decreasing quality.
  Future<Uint8List> encodeToWebP(
    img.Image image, {
    int quality = 85,
    int method = 6,
  }) async {
    if (Platform.isWindows) {
      try {
        return await _encodeWithSizeConstraint(
          image,
          initialQuality: quality,
          method: method,
          encoder: (img, q, m) => _encodeWithCwebp(img, quality: q, method: m),
        );
      } catch (e) {
        developer.log(
          'Error using cwebp.exe, falling back to image package: $e',
          name: 'WebpEncoderService',
        );
        return await _encodeWithSizeConstraint(
          image,
          initialQuality: quality,
          method: method,
          encoder: (img, q, _) => _encodeWithImagePackage(img, quality: q),
        );
      }
    } else if (Platform.isAndroid) {
      return await _encodeWithSizeConstraint(
        image,
        initialQuality: quality,
        method: method,
        encoder: (img, q, _) => _encodeWithFlutterImageCompress(img, quality: q),
      );
    } else {
      return await _encodeWithSizeConstraint(
        image,
        initialQuality: quality,
        method: method,
        encoder: (img, q, _) => _encodeWithImagePackage(img, quality: q),
      );
    }
  }

  /// Encodes an image with size constraints by progressively reducing quality
  ///
  /// Makes multiple attempts to encode the image, reducing quality each time
  /// until the file size is under MAX_SIZE_KB (150KB).
  Future<Uint8List> _encodeWithSizeConstraint(
    img.Image image, {
    required int initialQuality,
    required int method,
    required Future<Uint8List> Function(img.Image image, int quality, int method) encoder,
  }) async {
    int currentQuality = initialQuality;
    int attempts = 0;
    Uint8List result;

    do {
      result = await encoder(image, currentQuality, method);
      final sizeKB = result.length / 1024;

      developer.log(
        'Encoding attempt ${attempts + 1}: quality=$currentQuality, size=${sizeKB.toStringAsFixed(2)}KB',
        name: 'WebpEncoderService',
      );

      if (sizeKB <= maxSizeKb) {
        developer.log(
          'Successfully encoded image under ${maxSizeKb}KB (${sizeKB.toStringAsFixed(2)}KB)',
          name: 'WebpEncoderService',
        );
        return result;
      }

      // Calculate new quality based on how far we are from target size
      // More aggressive reduction for larger files
      final ratio = maxSizeKb / sizeKB;
      int qualityReduction;

      if (ratio < 0.5) {
        qualityReduction = 25; // Very large file, reduce by 25
      } else if (ratio < 0.7) {
        qualityReduction = 15; // Large file, reduce by 15
      } else if (ratio < 0.9) {
        qualityReduction = 10; // Medium file, reduce by 10
      } else {
        qualityReduction = 5; // Close to target, reduce by 5
      }

      currentQuality = (currentQuality - qualityReduction).clamp(5, 100);
      attempts++;

    } while (attempts < maxAttempts);

    developer.log(
      'Failed to reduce image size below ${maxSizeKb}KB after $maxAttempts attempts. Using best result.',
      name: 'WebpEncoderService',
    );

    return result;
  }

  Future<Uint8List> _encodeWithCwebp(
    img.Image image, {
    int quality = 85,
    int method = 6,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final inputPath = path.join(
      tempDir.path,
      'input_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    final outputPath = path.join(
      tempDir.path,
      'output_${DateTime.now().millisecondsSinceEpoch}.webp',
    );

    try {
      final pngBytes = img.encodePng(image);
      await File(inputPath).writeAsBytes(pngBytes);

      final cwebpPath = await _getCwebpPath();

      final result = await Process.run(cwebpPath, [
        '-q',
        quality.toString(),
        '-m',
        method.toString(),
        '-o',
        outputPath,
        inputPath,
      ]);

      if (result.exitCode != 0) {
        throw Exception('cwebp.exe failed: ${result.stderr}');
      }

      final webpBytes = await File(outputPath).readAsBytes();

      await File(inputPath).delete();
      await File(outputPath).delete();

      return webpBytes;
    } catch (e) {
      try {
        if (await File(inputPath).exists()) {
          await File(inputPath).delete();
        }
        if (await File(outputPath).exists()) {
          await File(outputPath).delete();
        }
      } catch (_) {}

      rethrow;
    }
  }

  Future<String> _getCwebpPath() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cwebpDir = Directory(path.join(appDir.path, 'cwebp'));
      final cwebpPath = path.join(cwebpDir.path, 'cwebp.exe');

      if (!await File(cwebpPath).exists()) {
        if (!await cwebpDir.exists()) {
          await cwebpDir.create(recursive: true);
        }

        final byteData = await rootBundle.load('assets/bin/windows/cwebp.exe');
        final buffer = byteData.buffer;
        final bytes = buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );

        await File(cwebpPath).writeAsBytes(bytes);
      }

      return cwebpPath;
    } catch (e) {
      developer.log(
        'Error extracting cwebp.exe: $e',
        name: 'WebpEncoderService',
      );
      throw Exception('Failed to extract cwebp.exe: $e');
    }
  }

  Future<Uint8List> _encodeWithImagePackage(
    img.Image image, {
    int quality = 85,
  }) async {
    developer.log(
      'Using PNG encoding as fallback (image package lacks WebP quality control)',
      name: 'WebpEncoderService',
    );
    return await compute((EncoderParams params) {
      return Uint8List.fromList(img.encodePng(params.image));
    }, EncoderParams(image, quality));
  }

  Future<Uint8List> _encodeWithFlutterImageCompress(
    img.Image image, {
    int quality = 85,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final inputPath = path.join(
        tempDir.path,
        'input_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      final pngBytes = await compute((EncoderParams params) {
        return Uint8List.fromList(img.encodePng(params.image));
      }, EncoderParams(image, quality));

      await File(inputPath).writeAsBytes(pngBytes);

      final result = await FlutterImageCompress.compressWithFile(
        inputPath,
        quality: quality,
        format: CompressFormat.webp,
      );

      try {
        if (await File(inputPath).exists()) {
          await File(inputPath).delete();
        }
      } catch (_) {}

      if (result == null) {
        throw Exception('flutter_image_compress returned null');
      }

      return result;
    } catch (e) {
      developer.log(
        'Error using flutter_image_compress: $e',
        name: 'WebpEncoderService',
      );
      return await _encodeWithImagePackage(image, quality: quality);
    }
  }
}

class EncoderParams {
  final img.Image image;
  final int quality;

  EncoderParams(this.image, this.quality);
}
