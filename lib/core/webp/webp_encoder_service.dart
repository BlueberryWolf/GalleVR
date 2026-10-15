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

  /// Encodes to WebP under 150KB, lowering quality over up to 5 attempts.
  ///
  /// cwebp does the resizing on Windows and Linux.
  Future<Uint8List> encodeToWebP(
    img.Image image, {
    int quality = 85,
    int method = 6,
    bool useResizing = true,
  }) async {
    final originalWidth = image.width;
    final originalHeight = image.height;

    if (Platform.isWindows || Platform.isLinux) {
      try {
        // cwebp resizes on Windows and Linux, so the original image is passed through.
        return await _encodeWithSizeConstraint(
          image,
          initialQuality: quality,
          method: method,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          useResizing: useResizing,
          encoder:
              (img, q, m, w, h, resize) => _encodeWithCwebp(
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
        final resizedImage = await _resizeImageIfNeeded(image);
        return await _encodeWithSizeConstraint(
          resizedImage,
          initialQuality: quality,
          method: method,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          useResizing: false, // Already resized
          encoder:
              (img, q, m, _, __, ___) =>
                  _encodeWithImagePackage(img, quality: q),
        );
      }
    } else if (Platform.isAndroid) {
      final resizedImage = await _resizeImageIfNeeded(image);
      final tempDir = await getTemporaryDirectory();
      final tempPngPath = path.join(
        tempDir.path,
        'temp_encode_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      try {
        final pngBytes = await compute((img.Image imgObj) {
          return Uint8List.fromList(img.encodePng(imgObj));
        }, resizedImage);
        await File(tempPngPath).writeAsBytes(pngBytes);

        return await _encodeWithSizeConstraint(
          resizedImage,
          initialQuality: quality,
          method: method,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          useResizing: false, // Already resized
          encoder: (img, q, m, _, __, ___) async {
            final compressed = await FlutterImageCompress.compressWithFile(
              tempPngPath,
              quality: q,
              format: CompressFormat.webp,
            );
            if (compressed == null) {
              throw Exception('flutter_image_compress returned null');
            }
            return compressed;
          },
        );
      } finally {
        try {
          final tempFile = File(tempPngPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    } else {
      final resizedImage = await _resizeImageIfNeeded(image);
      return await _encodeWithSizeConstraint(
        resizedImage,
        initialQuality: quality,
        method: method,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        useResizing: false, // Already resized
        encoder:
            (img, q, m, _, __, ___) => _encodeWithImagePackage(img, quality: q),
      );
    }
  }

  /// Lowers quality each attempt until the output is under [maxSizeKb].
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
      bool useResizing,
    )
    encoder,
    int? originalWidth,
    int? originalHeight,
    bool useResizing = true,
  }) async {
    int currentQuality = initialQuality;
    int attempts = 0;
    Uint8List result;

    int? targetWidth;
    int? targetHeight;

    if (originalWidth != null && originalHeight != null && useResizing) {
      const maxDimension = 1080;

      if (originalWidth > originalHeight) {
        if (originalHeight > maxDimension) {
          targetHeight = maxDimension;
          targetWidth =
              (originalWidth * (maxDimension / originalHeight)).round();
        } else {
          targetWidth = originalWidth;
          targetHeight = originalHeight;
        }
      } else {
        if (originalWidth > maxDimension) {
          targetWidth = maxDimension;
          targetHeight =
              (originalHeight * (maxDimension / originalWidth)).round();
        } else {
          targetWidth = originalWidth;
          targetHeight = originalHeight;
        }
      }

      developer.log(
        'Target dimensions: ${targetWidth}x$targetHeight (original: ${originalWidth}x$originalHeight)',
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

      // Reduce quality more aggressively the further the file is over the target size.
      final ratio = maxSizeKb / sizeKB;
      int qualityReduction;

      if (ratio < 0.5) {
        qualityReduction = 25;
      } else if (ratio < 0.7) {
        qualityReduction = 15;
      } else if (ratio < 0.9) {
        qualityReduction = 10;
      } else {
        qualityReduction = 5;
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

  /// Fits the image within 1080px, keeping its aspect ratio.
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

      if (targetWidth != null && targetHeight != null) {
        args.addAll([
          '-resize',
          targetWidth.toString(),
          targetHeight.toString(),
        ]);
      }

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

        // ensure the binary is executable on linux
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

  /// Uses cwebp on Windows and Linux, FlutterImageCompress on Android.
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
        try {
          final file = File(inputPath);
          final raf = await file.open(mode: FileMode.read);
          final headerBytes = await raf.read(24);
          await raf.close();

          if (headerBytes.length >= 24 &&
              headerBytes[0] == 0x89 &&
              headerBytes[1] == 0x50 &&
              headerBytes[2] == 0x4E &&
              headerBytes[3] == 0x47) {
            final bd = ByteData.sublistView(headerBytes);
            width = bd.getInt32(16, Endian.big);
            height = bd.getInt32(20, Endian.big);
          }
        } catch (_) {}
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

class EncoderParams {
  final img.Image image;
  final int quality;

  EncoderParams(this.image, this.quality);
}
