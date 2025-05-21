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
  /// On Windows, uses cwebp's built-in resizing capability.
  Future<Uint8List> encodeToWebP(
    img.Image image, {
    int quality = 85,
    int method = 6,
    bool useResizing = true,
  }) async {
    // Store original dimensions for Windows resizing
    final originalWidth = image.width;
    final originalHeight = image.height;

    if (Platform.isWindows) {
      try {
        // For Windows, we'll pass the original image and let cwebp handle resizing
        return await _encodeWithSizeConstraint(
          image,
          initialQuality: quality,
          method: method,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          useResizing: useResizing,
          encoder: (img, q, m, w, h, resize) => _encodeWithCwebp(
            img,
            quality: q,
            method: m,
            targetWidth: resize ? w : null,
            targetHeight: resize ? h : null,
          ),
        );
      } catch (e) {
        developer.log(
          'Error using cwebp.exe, falling back to image package: $e',
          name: 'WebpEncoderService',
        );
        // For fallback, we'll use the resized image
        final resizedImage = await _resizeImageIfNeeded(image);
        return await _encodeWithSizeConstraint(
          resizedImage,
          initialQuality: quality,
          method: method,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          useResizing: false, // Already resized
          encoder: (img, q, m, _, __, ___) => _encodeWithImagePackage(img, quality: q),
        );
      }
    } else if (Platform.isAndroid) {
      // For Android, resize the image first
      final resizedImage = await _resizeImageIfNeeded(image);
      return await _encodeWithSizeConstraint(
        resizedImage,
        initialQuality: quality,
        method: method,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        useResizing: false, // Already resized
        encoder: (img, q, m, _, __, ___) => _encodeWithFlutterImageCompress(img, quality: q),
      );
    } else {
      // For other platforms, resize the image first
      final resizedImage = await _resizeImageIfNeeded(image);
      return await _encodeWithSizeConstraint(
        resizedImage,
        initialQuality: quality,
        method: method,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        useResizing: false, // Already resized
        encoder: (img, q, m, _, __, ___) => _encodeWithImagePackage(img, quality: q),
      );
    }
  }

  /// Encodes an image with size constraints by progressively reducing quality
  ///
  /// Makes multiple attempts to encode the image, reducing quality each time
  /// until the file size is under maxSizeKb (150KB).
  Future<Uint8List> _encodeWithSizeConstraint(
    img.Image image, {
    required int initialQuality,
    required int method,
    required Future<Uint8List> Function(
      img.Image image,
      int quality,
      int method,
      int? targetWidth,
      int? targetHeight,
      bool useResizing
    ) encoder,
    int? originalWidth,
    int? originalHeight,
    bool useResizing = true,
  }) async {
    int currentQuality = initialQuality;
    int attempts = 0;
    Uint8List result;

    // Calculate target dimensions for 1080p
    int? targetWidth;
    int? targetHeight;

    if (originalWidth != null && originalHeight != null && useResizing) {
      const maxDimension = 1080;

      if (originalWidth > originalHeight) {
        if (originalHeight > maxDimension) {
          targetHeight = maxDimension;
          targetWidth = (originalWidth * (maxDimension / originalHeight)).round();
        } else {
          targetWidth = originalWidth;
          targetHeight = originalHeight;
        }
      } else {
        if (originalWidth > maxDimension) {
          targetWidth = maxDimension;
          targetHeight = (originalHeight * (maxDimension / originalWidth)).round();
        } else {
          targetWidth = originalWidth;
          targetHeight = originalHeight;
        }
      }

      developer.log(
        'Target dimensions: ${targetWidth}x${targetHeight} (original: ${originalWidth}x${originalHeight})',
        name: 'WebpEncoderService',
      );
    }

    do {
      result = await encoder(
        image,
        currentQuality,
        method,
        targetWidth,
        targetHeight,
        useResizing,
      );
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

  /// Resizes an image to fit within 1080p dimensions while maintaining aspect ratio
  Future<img.Image> _resizeImageIfNeeded(img.Image image) async {
    const maxDimension = 1080;

    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }

    return await compute((img.Image image) {
      int newWidth, newHeight;

      if (image.width > image.height) {
        if (image.height > maxDimension) {
          newHeight = maxDimension;
          newWidth = (image.width * (maxDimension / image.height)).round();
        } else {
          newWidth = image.width;
          newHeight = image.height;
        }
      } else {
        if (image.width > maxDimension) {
          newWidth = maxDimension;
          newHeight = (image.height * (maxDimension / image.width)).round();
        } else {
          newWidth = image.width;
          newHeight = image.height;
        }
      }

      return img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic,
      );
    }, image);
  }

  Future<Uint8List> _encodeWithCwebp(
    img.Image image, {
    int quality = 85,
    int method = 6,
    int? targetWidth,
    int? targetHeight,
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

      final args = [
        '-q',
        quality.toString(),
        '-m',
        method.toString(),
        '-o',
        outputPath,
      ];

      // Add resize parameters if provided
      if (targetWidth != null && targetHeight != null) {
        args.addAll([
          '-resize',
          targetWidth.toString(),
          targetHeight.toString(),
        ]);
      }

      // Add input path at the end
      args.add(inputPath);

      developer.log(
        'Running cwebp with args: $args',
        name: 'WebpEncoderService',
      );

      final result = await Process.run(cwebpPath, args);

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
