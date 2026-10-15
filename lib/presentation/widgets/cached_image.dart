import 'dart:io';
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
  final double opacity;
  final bool greyscale;

  const CachedImage({
    super.key,
    required this.filePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.thumbnailSize,
    this.highQuality = false,
    this.useOriginal = false,
    this.opacity = 1.0,
    this.greyscale = false,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _thumbnailFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.thumbnailSize != widget.thumbnailSize) {
      _loadImage();
    }
  }

  Future<void> _loadImage({bool isRetry = false}) async {
    if (!mounted || widget.useOriginal) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final file = await ImageCacheService().getThumbnailFile(
        widget.filePath,
        size: widget.thumbnailSize ?? 300,
      );

      if (mounted) {
        if (file == null && !isRetry) {
          await Future.delayed(const Duration(milliseconds: 200));
          return _loadImage(isRetry: true);
        }

        setState(() {
          _thumbnailFile = file;
          _isLoading = false;
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
      return LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final maxW = widget.width ?? constraints.maxWidth;
          final maxH = widget.height ?? constraints.maxHeight;
          ImageProvider provider = FileImage(File(widget.filePath));
          if (maxW.isFinite && maxH.isFinite) {
            provider = ResizeImage(
              provider,
              width: (maxW * dpr * 2).round(),
              height: (maxH * dpr * 2).round(),
              policy: ResizeImagePolicy.fit,
              allowUpscaling: false,
            );
          }
          return Image(
            image: provider,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            gaplessPlayback: true,
            filterQuality:
                widget.highQuality ? FilterQuality.high : FilterQuality.medium,
            opacity: AlwaysStoppedAnimation(widget.opacity),
            errorBuilder: _errorBuilder,
          );
        },
      );
    }

    if (_isLoading && _thumbnailFile == null) {
      return Container(color: Colors.grey[900]);
    }

    final displayFile = _thumbnailFile ?? File(widget.filePath);

    final image = Image.file(
      displayFile,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      filterQuality:
          widget.highQuality ? FilterQuality.high : FilterQuality.low,
      opacity: AlwaysStoppedAnimation(widget.opacity),
      cacheWidth: widget.thumbnailSize ?? 300,
      errorBuilder: _errorBuilder,
    );
    if (!widget.greyscale) return image;
    return ColorFiltered(colorFilter: _greyscaleFilter, child: image);
  }

  static const _lumaR = 0.2126, _lumaG = 0.7152, _lumaB = 0.0722;
  static const _greyscaleFilter = ColorFilter.matrix(<double>[
    _lumaR,
    _lumaG,
    _lumaB,
    0,
    0,
    _lumaR,
    _lumaG,
    _lumaB,
    0,
    0,
    _lumaR,
    _lumaG,
    _lumaB,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  static Widget _errorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      color: Colors.grey[800],
      child: const Icon(Icons.broken_image, color: Colors.grey, size: 20),
    );
  }
}
