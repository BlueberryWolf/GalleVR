import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/image/image_cache_service.dart';
import '../theme/app_theme.dart';

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

  static final Map<String, Map<(int, int), ImageProvider>> _originalProviders =
      {};

  static final Map<String, ImageProvider> _thumbnailProviders = {};

  static void evictOriginal(String filePath) {
    final providers = _originalProviders.remove(filePath)?.values ?? const [];
    for (final provider in providers) {
      provider.evict();
    }
  }
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
          final size =
              maxW.isFinite && maxH.isFinite
                  ? ((maxW * dpr * 2).round(), (maxH * dpr * 2).round())
                  : (0, 0);
          final provider = CachedImage._originalProviders
              .putIfAbsent(widget.filePath, () => {})
              .putIfAbsent(size, () {
                final file = FileImage(File(widget.filePath));
                if (size == (0, 0)) return file;
                return ResizeImage(
                  file,
                  width: size.$1,
                  height: size.$2,
                  policy: ResizeImagePolicy.fit,
                  allowUpscaling: false,
                );
              });
          final placeholder = CachedImage._thumbnailProviders[widget.filePath];
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
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null || wasSynchronouslyLoaded) return child;
              if (placeholder == null) return child;
              return Image(
                image: placeholder,
                fit: widget.fit,
                width: maxW.isFinite ? maxW : null,
                height: maxH.isFinite ? maxH : null,
                filterQuality: FilterQuality.medium,
              );
            },
          );
        },
      );
    }

    if (_isLoading && _thumbnailFile == null) {
      return Container(color: AppTheme.surfaceBase);
    }

    final displayFile = _thumbnailFile ?? File(widget.filePath);

    final provider = ResizeImage.resizeIfNeeded(
      widget.thumbnailSize ?? 300,
      null,
      FileImage(displayFile),
    );
    CachedImage._thumbnailProviders[widget.filePath] = provider;
    final image = Image(
      image: provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      filterQuality:
          widget.highQuality ? FilterQuality.high : FilterQuality.low,
      opacity: AlwaysStoppedAnimation(widget.opacity),
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
      color: AppTheme.buttonColor,
      child: const Icon(
        Icons.broken_image,
        color: AppTheme.secondaryTextColor,
        size: 20,
      ),
    );
  }
}
