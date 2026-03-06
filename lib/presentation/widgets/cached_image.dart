import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/image/image_cache_service.dart';

class CachedImage extends StatefulWidget {
  final String filePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? thumbnailSize;
  final bool highQuality;
  final bool useOriginal;

  const CachedImage({
    super.key,
    required this.filePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.thumbnailSize,
    this.highQuality = false,
    this.useOriginal = false,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath || oldWidget.thumbnailSize != widget.thumbnailSize) {
      _loadImage();
    }
  }

  Future<void> _loadImage({bool isRetry = false}) async {
    if (!mounted || widget.useOriginal) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final data = await ImageCacheService().getThumbnail(
        widget.filePath,
        size: widget.thumbnailSize ?? 300,
      );
      
      if (mounted) {
        if (data == null && !isRetry) {
          await Future.delayed(const Duration(milliseconds: 200));
          return _loadImage(isRetry: true);
        }

        setState(() {
          _imageData = data;
          _isLoading = false;
          _hasError = data == null;
        });
      }
    } catch (e) {
      if (mounted) {
        if (!isRetry) {
          await Future.delayed(const Duration(milliseconds: 200));
          return _loadImage(isRetry: true);
        }
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.transparent,
      child: _buildContent(),
    );
  }
  
  Widget _buildContent() {
    if (widget.useOriginal) {
      return Image.file(
        File(widget.filePath),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        filterQuality: widget.highQuality ? FilterQuality.high : FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[800],
            child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
          );
        },
      );
    }

    if (_isLoading && _imageData == null) {
      return Container(color: Colors.grey[900]);
    }
    
    if (_hasError || _imageData == null) {
      return Container(
        color: Colors.grey[800],
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
      );
    }

    return Image.memory(
      _imageData!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      filterQuality: widget.highQuality ? FilterQuality.high : FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[800],
          child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
        );
      },
    );
  }
}
