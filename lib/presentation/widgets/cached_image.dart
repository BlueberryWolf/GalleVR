import 'dart:collection';
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

  static const int _maxThumbnailProviders = 64;

  static final Map<String, Map<(int, int), ImageProvider>> _originalProviders =
      {};

  static final LinkedHashMap<String, ImageProvider> _thumbnailProviders =
      LinkedHashMap<String, ImageProvider>();

  static void _recordThumbnailProvider(String filePath, ImageProvider provider) {
    _thumbnailProviders.remove(filePath);
    _thumbnailProviders[filePath] = provider;
    while (_thumbnailProviders.length > _maxThumbnailProviders) {
      _thumbnailProviders.remove(_thumbnailProviders.keys.first);
    }
  }

  static void evictOriginal(String filePath) {
    final providers = _originalProviders.remove(filePath)?.values ?? const [];
    for (final provider in providers) {
      provider.evict();
    }
  }

  static void clearAllProviders() {
    for (final map in _originalProviders.values) {
      for (final provider in map.values) {
        provider.evict();
      }
    }
    _originalProviders.clear();

    for (final provider in _thumbnailProviders.values) {
      provider.evict();
    }
    _thumbnailProviders.clear();
  }
}

class _CachedImageState extends State<CachedImage> {
  File? _thumbnailFile;
  ImageProvider? _cachedThumbnailProvider;
  String? _cachedThumbnailKey;
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
      _cachedThumbnailProvider = null;
      _cachedThumbnailKey = null;
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
          await _loadImage(isRetry: true);
          return;
        }

        setState(() {
          _thumbnailFile = file;
          _cachedThumbnailProvider = null;
          _cachedThumbnailKey = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (!isRetry) {
          await Future.delayed(const Duration(milliseconds: 200));
          await _loadImage(isRetry: true);
          return;
        }
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  ImageProvider _resolveThumbnailProvider(File displayFile, int targetWidth) {
    final key = '${displayFile.path}#$targetWidth';
    if (_cachedThumbnailProvider != null && _cachedThumbnailKey == key) {
      return _cachedThumbnailProvider!;
    }
    final provider = ResizeImage.resizeIfNeeded(
      targetWidth,
      null,
      FileImage(displayFile),
    );
    _cachedThumbnailProvider = provider;
    _cachedThumbnailKey = key;
    CachedImage._recordThumbnailProvider(widget.filePath, provider);
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (widget.useOriginal) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final window = MediaQuery.sizeOf(context);
          final maxW = widget.width ?? constraints.maxWidth;
          final maxH = widget.height ?? constraints.maxHeight;
          final size =
              window.isEmpty
                  ? (0, 0)
                  : (
                    (window.width * dpr * 1.5).round().clamp(512, 2560),
                    (window.height * dpr * 1.5).round().clamp(512, 2560),
                  );
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
      return const ColoredBox(color: AppTheme.surfaceBase);
    }

    final displayFile = _thumbnailFile ?? File(widget.filePath);
    final provider = _resolveThumbnailProvider(
      displayFile,
      widget.thumbnailSize ?? 300,
    );

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
    return const ColoredBox(
      color: AppTheme.buttonColor,
      child: Center(
        child: Icon(
          Icons.broken_image,
          color: AppTheme.secondaryTextColor,
          size: 20,
        ),
      ),
    );
  }
}
