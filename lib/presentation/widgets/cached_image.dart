import 'dart:io';
import 'package:flutter/material.dart';

class CachedImage extends StatefulWidget {
  final String filePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int thumbnailSize;
  final bool highQuality;

  const CachedImage({
    super.key,
    required this.filePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.thumbnailSize = 300,
    this.highQuality = false,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.transparent,
      child: Image.file(
        File(widget.filePath),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.highQuality ? null : widget.thumbnailSize,
        filterQuality: widget.highQuality ? FilterQuality.high : FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[800],
            child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
          );
        },
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            return child;
          }
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: child,
          );
        },
      ),
    );
  }
}
