import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class WebpEncoderService {
  Future<Uint8List> encodeToWebP(
    img.Image image, {
    int quality = 85,
    int method = 6,
  }) async {
    if (Platform.isWindows) {
      try {
        return await _encodeWithCwebp(image, quality: quality, method: method);
      } catch (e) {
        developer.log(
          'Error using cwebp.exe, falling back to image package: $e',
          name: 'WebpEncoderService',
        );
        return await _encodeWithImagePackage(image, quality: quality);
      }
    } else if (Platform.isAndroid) {
      return await _encodeWithFlutterImageCompress(image, quality: quality);
    } else {
      return await _encodeWithImagePackage(image, quality: quality);
    }
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
        '-size',
        '150000',
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
        quality: 20,
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
