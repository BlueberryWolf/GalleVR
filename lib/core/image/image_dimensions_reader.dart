import 'dart:io';
import 'dart:typed_data';

class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions(this.width, this.height);
}

/// Reads width and height from header.
class ImageDimensionsReader {
  static Future<ImageDimensions?> readFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final fileLength = await raf.length();
      if (fileLength < 10) return null;

      final header = await raf.read(32);
      if (header.length < 10) return null;

      // PNG
      if (header.length >= 24 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47 &&
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A) {
        final bd = ByteData.sublistView(header);
        final width = bd.getUint32(16, Endian.big);
        final height = bd.getUint32(20, Endian.big);
        if (width > 0 && height > 0) {
          return ImageDimensions(width, height);
        }
        return null;
      }

      // WebP
      if (header.length >= 30 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return _parseWebpHeader(header);
      }

      // JPEG
      if (header[0] == 0xFF && header[1] == 0xD8) {
        return await _parseJpeg(raf, fileLength);
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  static ImageDimensions? _parseWebpHeader(Uint8List header) {
    final bd = ByteData.sublistView(header);
    final c0 = header[12];
    final c1 = header[13];
    final c2 = header[14];
    final c3 = header[15];

    // 'VP8 ' (lossy)
    if (c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x20) {
      if (header[23] == 0x9D && header[24] == 0x01 && header[25] == 0x2A) {
        final width = bd.getUint16(26, Endian.little) & 0x3FFF;
        final height = bd.getUint16(28, Endian.little) & 0x3FFF;
        if (width > 0 && height > 0) {
          return ImageDimensions(width, height);
        }
      }
      return null;
    }

    // 'VP8L' (lossless)
    if (c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x4C) {
      if (header[20] == 0x2F) {
        final bits = bd.getUint32(21, Endian.little);
        final width = (bits & 0x3FFF) + 1;
        final height = ((bits >> 14) & 0x3FFF) + 1;
        if (width > 0 && height > 0) {
          return ImageDimensions(width, height);
        }
      }
      return null;
    }

    // 'VP8X' (extended)
    if (c0 == 0x56 && c1 == 0x50 && c2 == 0x38 && c3 == 0x58) {
      final width =
          1 + (header[24] | (header[25] << 8) | (header[26] << 16));
      final height =
          1 + (header[27] | (header[28] << 8) | (header[29] << 16));
      if (width > 0 && height > 0) {
        return ImageDimensions(width, height);
      }
      return null;
    }

    return null;
  }

  static Future<ImageDimensions?> _parseJpeg(
    RandomAccessFile raf,
    int fileLength,
  ) async {
    int offset = 2;
    while (offset + 4 <= fileLength) {
      await raf.setPosition(offset);
      final markerBuf = await raf.read(2);
      if (markerBuf.length < 2) return null;

      if (markerBuf[0] != 0xFF) {
        offset++;
        continue;
      }

      int marker = markerBuf[1];
      offset += 2;
      while (marker == 0xFF && offset < fileLength) {
        final next = await raf.read(1);
        if (next.isEmpty) return null;
        marker = next[0];
        offset++;
      }

      if (marker == 0xDA || marker == 0xD9) return null;

      if ((marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0xD8 ||
          marker == 0x01) {
        continue;
      }

      if (offset + 2 > fileLength) return null;
      final lenBuf = await raf.read(2);
      if (lenBuf.length < 2) return null;
      final segmentLen = (lenBuf[0] << 8) | lenBuf[1];
      if (segmentLen < 2) return null;

      final isSof =
          (marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF);

      if (isSof) {
        if (offset + 7 > fileLength) return null;
        final sofData = await raf.read(5);
        if (sofData.length < 5) return null;
        final height = (sofData[1] << 8) | sofData[2];
        final width = (sofData[3] << 8) | sofData[4];
        if (width > 0 && height > 0) {
          return ImageDimensions(width, height);
        }
        return null;
      }

      offset += segmentLen;
    }
    return null;
  }
}
