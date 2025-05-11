import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/image/thumbnail_provider.dart';

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

class _CachedImageState extends State<CachedImage> with WidgetsBindingObserver {
  final ImageCacheService _imageCacheService = ImageCacheService();
  final ThumbnailProvider _thumbnailProvider = ThumbnailProvider();

  final ValueNotifier<Uint8List?> _thumbnailNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _hasErrorNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isHighQualityLoadedNotifier = ValueNotifier(false);

  bool _isVisible = true;
  bool _loadingCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThumbnail();
  }

  @override
  void dispose() {
    _loadingCancelled = true;

    _thumbnailNotifier.dispose();
    _isLoadingNotifier.dispose();
    _hasErrorNotifier.dispose();
    _isHighQualityLoadedNotifier.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _loadingCancelled = true;
    } else if (state == AppLifecycleState.resumed && _isVisible) {
      if (_thumbnailNotifier.value == null && _isLoadingNotifier.value) {
        _loadingCancelled = false;
        _loadThumbnail();
      }
    }
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.thumbnailSize != widget.thumbnailSize) {
      _loadingCancelled = true;
      _loadingCancelled = false;
      _loadThumbnail();
    }
  }

  void setVisibility(bool isVisible) {
    if (_isVisible != isVisible) {
      _isVisible = isVisible;

      if (isVisible && _thumbnailNotifier.value == null && !_loadingCancelled) {
        _loadThumbnail();
      } else if (!isVisible && widget.highQuality) {
        _loadingCancelled = true;
      }
    }
  }

  Future<void> _loadThumbnail() async {
    if (!mounted || _loadingCancelled) return;

    _isLoadingNotifier.value = true;
    _hasErrorNotifier.value = false;
    _isHighQualityLoadedNotifier.value = false;

    try {
      final cachedThumbnail = _thumbnailProvider.getThumbnail(widget.filePath);
      if (cachedThumbnail != null) {
        _thumbnailNotifier.value = cachedThumbnail;
        _isLoadingNotifier.value = false;

        if (widget.highQuality && _isVisible) {
          _loadHighQualityImage();
        }
        return;
      }

      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted && !_loadingCancelled) {
          _isLoadingNotifier.value = false;
          _hasErrorNotifier.value = true;
        }
        return;
      }

      if (!mounted || _loadingCancelled) return;

      final bytes = await _imageCacheService.getThumbnail(
        widget.filePath,
        size: widget.thumbnailSize,
      );

      if (!mounted || _loadingCancelled) return;

      if (bytes != null) {
        _thumbnailNotifier.value = bytes;
        _isLoadingNotifier.value = false;
        _thumbnailProvider.setThumbnail(widget.filePath, bytes);

        if (widget.highQuality && _isVisible) {
          _loadHighQualityImage();
        }
      } else {
        _isLoadingNotifier.value = false;

        if (widget.highQuality && _isVisible) {
          _isHighQualityLoadedNotifier.value = true;
        } else {
          _hasErrorNotifier.value = true;
        }
      }
    } catch (e) {
      if (!mounted || _loadingCancelled) return;

      _isLoadingNotifier.value = false;
      _hasErrorNotifier.value = true;
    }
  }

  Future<void> _loadHighQualityImage() async {
    await Future.delayed(Duration(
      milliseconds: widget.highQuality ? 300 : 50
    ));

    if (!mounted || _loadingCancelled || !_isVisible) return;

    try {
      final file = File(widget.filePath);
      final exists = await file.exists();

      if (!mounted || _loadingCancelled) return;

      if (exists) {
        _isHighQualityLoadedNotifier.value = true;
      } else {
        _hasErrorNotifier.value = true;
      }
    } catch (e) {
      if (!mounted || _loadingCancelled) return;
      _hasErrorNotifier.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('cached_image_${widget.filePath}'),
      onVisibilityChanged: (info) {
        setVisibility(info.visibleFraction > 0.1);
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        color: Colors.transparent,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoadingNotifier,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return _buildLoadingPlaceholder();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _hasErrorNotifier,
          builder: (context, hasError, _) {
            if (hasError) {
              return _buildErrorWidget();
            }

            return ValueListenableBuilder<Uint8List?>(
              valueListenable: _thumbnailNotifier,
              builder: (context, thumbnailBytes, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _isHighQualityLoadedNotifier,
                  builder: (context, isHighQualityLoaded, _) {
                    if (thumbnailBytes != null && (!widget.highQuality || !isHighQualityLoaded)) {
                      return RepaintBoundary(
                        child: Image.memory(
                          thumbnailBytes,
                          fit: widget.fit,
                          width: widget.width,
                          height: widget.height,
                          cacheWidth: widget.thumbnailSize,
                          gaplessPlayback: true,
                          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                            if (wasSynchronouslyLoaded) return child;
                            return AnimatedOpacity(
                              opacity: frame != null ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeOut,
                              child: child,
                            );
                          },
                        ),
                      );
                    }

                    if (widget.highQuality && isHighQualityLoaded) {
                      return Stack(
                        fit: StackFit.passthrough,
                        children: [
                          if (thumbnailBytes != null)
                            RepaintBoundary(
                              child: Image.memory(
                                thumbnailBytes,
                                fit: widget.fit,
                                width: widget.width,
                                height: widget.height,
                                gaplessPlayback: true,
                              ),
                            ),

                          RepaintBoundary(
                            child: Image.file(
                              File(widget.filePath),
                              fit: widget.fit,
                              width: widget.width,
                              height: widget.height,
                              gaplessPlayback: true,
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                return AnimatedOpacity(
                                  opacity: frame != null ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  child: child,
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                if (thumbnailBytes != null) {
                                  return const SizedBox.shrink();
                                }
                                return _buildErrorWidget();
                              },
                            ),
                          ),
                        ],
                      );
                    }

                    return RepaintBoundary(
                      child: Image.file(
                        File(widget.filePath),
                        fit: widget.fit,
                        width: widget.width,
                        height: widget.height,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildErrorWidget();
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Colors.grey,
          size: 20,
        ),
      ),
    );
  }
}
