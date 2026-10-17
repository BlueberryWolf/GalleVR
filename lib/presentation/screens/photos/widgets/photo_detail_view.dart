import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:pasteboard/pasteboard.dart';
import '../../../../core/image/image_cache_service.dart';
import '../../../../data/models/photo_metadata.dart';
import '../../../../data/models/config_model.dart';
import '../../../../data/repositories/photo_metadata_repository.dart';
import '../../../../data/repositories/config_repository.dart';
import '../../../../data/services/manual_upload_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/cached_image.dart';
import '../../../widgets/photo_metadata_panel.dart';
import '../photos_utils.dart';

class PhotoDetailView extends StatefulWidget {
  final List<FileSystemEntity> photos;
  final int initialIndex;
  final VoidCallback? onMetadataUpdated;

  const PhotoDetailView({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.onMetadataUpdated,
  });

  @override
  State<PhotoDetailView> createState() => _PhotoDetailViewState();
}

class _PhotoDetailViewState extends State<PhotoDetailView> {
  late PageController _pageController;
  late int _currentIndex;
  final PhotoMetadataRepository _metadataRepository = PhotoMetadataRepository();
  final ManualUploadService _manualUploadService = ManualUploadService();
  final ConfigRepository _configRepository = ConfigRepository();

  PhotoMetadata? _currentMetadata;
  ConfigModel? _config;
  bool _isLoadingMetadata = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _isMetadataPanelOpen = false;
  String? _uploadStatus;
  Timer? _metadataDebounceTimer;
  final Set<String> _loadedPaths = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _trackLoadedPhotos();
    _loadConfig();
    _loadCurrentMetadata();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bytesPerPhoto =
        (window.width * dpr * 2) * (window.height * dpr * 2) * 4;
    ImageCacheService.reserve(count: 3, bytes: (bytesPerPhoto * 3).ceil());
  }

  @override
  void dispose() {
    _metadataDebounceTimer?.cancel();
    _pageController.dispose();
    _loadedPaths.forEach(CachedImage.evictOriginal);
    ImageCacheService.reserve(count: 0, bytes: 0);
    super.dispose();
  }

  Future<void> _loadConfig() async {
    _config = await _configRepository.loadConfig();
  }

  Future<void> _loadCurrentMetadata() async {
    if (_currentIndex < 0 || _currentIndex >= widget.photos.length) return;

    setState(() => _isLoadingMetadata = true);
    final photo = widget.photos[_currentIndex];
    final meta = await _metadataRepository.getPhotoMetadataForFile(photo.path);

    if (mounted) {
      setState(() {
        _currentMetadata = meta;
        _isLoadingMetadata = false;
      });
    }
  }

  void _trackLoadedPhotos() {
    final nearby = {
      for (var i = _currentIndex - 1; i <= _currentIndex + 1; i++)
        if (i >= 0 && i < widget.photos.length) widget.photos[i].path,
    };
    for (final path in _loadedPaths.difference(nearby)) {
      CachedImage.evictOriginal(path);
    }
    _loadedPaths
      ..clear()
      ..addAll(nearby);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _trackLoadedPhotos();

    _metadataDebounceTimer?.cancel();
    _metadataDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _loadCurrentMetadata();
      }
    });
  }

  Future<void> _manualUpload() async {
    if (_config == null || _isUploading || _currentMetadata == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final photo = widget.photos[_currentIndex];
      final galleryUrl = await _manualUploadService.uploadPhoto(
        photo.path,
        _config!,
        onStatusUpdate: (status) => setState(() => _uploadStatus = status),
        onProgress: (p) => setState(() => _uploadProgress = p),
      );

      if (mounted && galleryUrl != null) {
        await _loadCurrentMetadata();
        widget.onMetadataUpdated?.call();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Uploaded successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final bool isActionable =
              event is KeyDownEvent || event is KeyRepeatEvent;
          if (!isActionable) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (_pageController.hasClients) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
              );
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (_pageController.hasClients) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
              );
            }
            return KeyEventResult.handled;
          } else if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: 0,
              top: 0,
              bottom: 0,
              right: _isMetadataPanelOpen ? 340 : 0,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    allowImplicitScrolling: true,
                    itemCount: widget.photos.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) {
                      final photo = widget.photos[index];
                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Center(
                          child: HeroMode(
                            enabled: index == _currentIndex,
                            child: Hero(
                              tag: photo.path,
                              child: CachedImage(
                                filePath: photo.path,
                                fit: BoxFit.contain,
                                useOriginal: true,
                                highQuality: true,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  if (_isMetadataPanelOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap:
                            () => setState(() => _isMetadataPanelOpen = false),
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),

                  if (_currentIndex > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 120,
                      child: _NavigationRegion(
                        icon: Icons.chevron_left_rounded,
                        onTap:
                            () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            ),
                      ),
                    ),

                  if (_currentIndex < widget.photos.length - 1)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 120,
                      child: _NavigationRegion(
                        icon: Icons.chevron_right_rounded,
                        onTap:
                            () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            ),
                      ),
                    ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildDynamicAppBar(),
                  ),

                  _buildActionPods(),

                  if (_isLoadingMetadata)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                ],
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              right: _isMetadataPanelOpen ? 0 : -340,
              top: 0,
              bottom: 0,
              width: 340,
              child: PhotoMetadataPanel(
                metadata: _currentMetadata,
                isOpen: true,
                onClose: () => setState(() => _isMetadataPanelOpen = false),
              ),
            ),

            if (_isUploading)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusCard,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 200,
                              child: LinearProgressIndicator(
                                value: _uploadProgress,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryColor,
                                ),
                              ),
                            ),
                            if (_uploadStatus != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _uploadStatus!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPods() {
    return Positioned(
      bottom: 32,
      left: 24,
      right: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ActionPod(
            children: [
              _PodButton(
                icon: Icons.people_alt_rounded,
                label: 'Info',
                onPressed:
                    () => setState(
                      () => _isMetadataPanelOpen = !_isMetadataPanelOpen,
                    ),
                badge: _currentMetadata?.players.length,
                isActive: _isMetadataPanelOpen,
                tooltip: 'Photo Info',
              ),
              if (_currentMetadata?.galleryUrl != null)
                _PodButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onPressed: () {
                    copyToClipboard(
                      text: _currentMetadata!.galleryUrl!,
                      context: context,
                      successMessage: 'Gallery URL copied',
                      onSuccess:
                          () => openUrl(_currentMetadata!.galleryUrl!, context),
                    );
                  },
                  tooltip: 'Share Link',
                ),
            ],
          ),

          _ActionPod(
            children: [
              _PodButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onPressed: () async {
                  final photo = widget.photos[_currentIndex];
                  final result = await Pasteboard.writeFiles([photo.path]);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result
                              ? 'Image copied to clipboard'
                              : 'Failed to copy image',
                        ),
                      ),
                    );
                  }
                },
                tooltip: 'Copy Image',
              ),
              _PodButton(
                icon: Icons.folder_open_rounded,
                label: 'File',
                onPressed:
                    () => showFileInExplorer(
                      widget.photos[_currentIndex].path,
                      context,
                    ),
                tooltip: 'Show in Explorer',
              ),
              if (_currentMetadata?.galleryUrl == null && !_isUploading)
                _PodButton(
                  icon: Icons.cloud_upload_rounded,
                  label: 'Upload',
                  activeColor: AppTheme.primaryColor,
                  onPressed: _manualUpload,
                  tooltip: 'Upload to Gallery',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicAppBar() {
    String dateStr = '';
    if (_currentMetadata != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        _currentMetadata!.takenDate,
      );
      dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    const textShadows = [Shadow(color: Color(0x99000000), blurRadius: 6)];

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x59000000), Color(0x00000000)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 96,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Row(
            children: [
              _OverlayIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _currentMetadata?.filename ??
                          path.basename(widget.photos[_currentIndex].path),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: textShadows,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dateStr.isNotEmpty)
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          shadows: textShadows,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPod extends StatelessWidget {
  final List<Widget> children;

  const _ActionPod({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _PodButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final int? badge;
  final bool isActive;
  final Color? activeColor;
  final String? tooltip;

  const _PodButton({
    required this.icon,
    this.label,
    required this.onPressed,
    this.badge,
    this.isActive = false,
    this.activeColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: label != null ? 14 : 10),
            height: 44,
            decoration: BoxDecoration(
              color:
                  isActive
                      ? (activeColor ?? Colors.white.withValues(alpha: 0.12))
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      color:
                          isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.8),
                      size: 22,
                    ),
                    if (badge != null && badge! > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$badge',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (label != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    label!,
                    style: TextStyle(
                      color:
                          isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_OverlayIconButton> createState() => _OverlayIconButtonState();
}

class _OverlayIconButtonState extends State<_OverlayIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(_isHovered ? 200 : 150),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: Colors.white.withAlpha(_isHovered ? 40 : 20),
              ),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _NavigationRegion extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavigationRegion({required this.icon, required this.onTap});

  @override
  State<_NavigationRegion> createState() => _NavigationRegionState();
}

class _NavigationRegionState extends State<_NavigationRegion> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(
                      color:
                          _isHovered
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 32,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          _isHovered
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: _isHovered ? 1.1 : 1.0,
                      child: Icon(widget.icon, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
