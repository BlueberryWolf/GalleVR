import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:pasteboard/pasteboard.dart';
import '../../../../core/image/image_cache_service.dart';
import '../../../../core/utils/tag_parser.dart';
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

  static const double _panelWidth = 360;

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
    final maxW = (window.width * dpr * 1.5).round().clamp(512, 2560);
    final maxH = (window.height * dpr * 1.5).round().clamp(512, 2560);
    final bytesPerPhoto = maxW * maxH * 4;
    ImageCacheService.reserve(count: 3, bytes: bytesPerPhoto * 3);
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
    for (final p in _loadedPaths.difference(nearby)) {
      CachedImage.evictOriginal(p);
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

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dt.month - 1];

    String daySuffix = 'th';
    if (dt.day == 1 || dt.day == 21 || dt.day == 31) {
      daySuffix = 'st';
    } else if (dt.day == 2 || dt.day == 22) {
      daySuffix = 'nd';
    } else if (dt.day == 3 || dt.day == 23) {
      daySuffix = 'rd';
    }

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    final minute = dt.minute.toString().padLeft(2, '0');

    return '$month ${dt.day}$daySuffix ${dt.year}, $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final currentFilename =
        _currentMetadata?.filename ??
        path.basename(widget.photos[_currentIndex].path);

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
            if (_isMetadataPanelOpen) {
              setState(() => _isMetadataPanelOpen = false);
            } else {
              Navigator.pop(context);
            }
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
              right: _isMetadataPanelOpen ? _panelWidth : 0,
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
                    child: _buildDynamicAppBar(currentFilename),
                  ),

                  _buildActionPods(),

                  if (_isLoadingMetadata)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.brandPurple,
                      ),
                    ),
                ],
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              right: _isMetadataPanelOpen ? 0 : -_panelWidth,
              top: 0,
              bottom: 0,
              width: _panelWidth,
              child: PhotoMetadataPanel(
                metadata: _currentMetadata,
                filename: currentFilename,
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
                          color: const Color(0xCC08080C),
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
                              width: 220,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: _uploadProgress,
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        AppTheme.brandPurple,
                                      ),
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
      bottom: 24,
      left: 20,
      right: 20,
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
                  icon: Icons.link_rounded,
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
                  tooltip: 'Copy Gallery Link',
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
                  accentColor: AppTheme.brandPurple,
                  onPressed: _manualUpload,
                  tooltip: 'Upload to Gallery',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicAppBar(String fallbackFilename) {
    final titleText =
        _currentMetadata != null
            ? _formatDate(_currentMetadata!.takenDate)
            : fallbackFilename;
    final world = _currentMetadata?.world;
    final worldName =
        world != null ? stripResoniteTags(world.name).trim() : '';
    final playerCount = _currentMetadata?.players.length ?? 0;
    final isUploaded = _currentMetadata?.galleryUrl != null;

    const textShadows = [
      Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1)),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x80000000), Color(0x33000000), Color(0x00000000)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        shadows: textShadows,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (worldName.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.public_rounded,
                                  size: 16,
                                  color: AppTheme.iconWorld,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text.rich(
                                    parseResoniteTags(
                                      world!.name,
                                      const TextStyle(
                                        color: Color(0xD9FFFFFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        shadows: textShadows,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (playerCount > 0)
                          _MetaClickableItem(
                            icon: Icons.people_alt_rounded,
                            iconColor: AppTheme.iconPlayers,
                            label: '$playerCount',
                            tooltip: 'View players',
                            onTap:
                                () => setState(
                                  () =>
                                      _isMetadataPanelOpen =
                                          !_isMetadataPanelOpen,
                                ),
                          ),
                        if (isUploaded)
                          const Tooltip(
                            message: 'Uploaded to Gallery',
                            child: Icon(
                              Icons.cloud_done_rounded,
                              size: 16,
                              color: AppTheme.successColor,
                            ),
                          ),
                      ],
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

class _MetaClickableItem extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _MetaClickableItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_MetaClickableItem> createState() => _MetaClickableItemState();
}

class _MetaClickableItemState extends State<_MetaClickableItem> {
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
          onTap: widget.onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: widget.iconColor),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isHovered ? Colors.white : const Color(0xD9FFFFFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration:
                      _isHovered
                          ? TextDecoration.underline
                          : TextDecoration.none,
                  decorationColor: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: const [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
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

class _ActionPod extends StatefulWidget {
  final List<Widget> children;

  const _ActionPod({required this.children});

  @override
  State<_ActionPod> createState() => _ActionPodState();
}

class _ActionPodState extends State<_ActionPod> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _isHovered ? 0.45 : 0.35),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: Colors.white.withValues(alpha: _isHovered ? 0.15 : 0.08),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 32,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
          ),
        ),
      ),
    );
  }
}

class _PodButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final int? badge;
  final bool isActive;
  final Color? accentColor;
  final String? tooltip;

  const _PodButton({
    required this.icon,
    this.label,
    required this.onPressed,
    this.badge,
    this.isActive = false,
    this.accentColor,
    this.tooltip,
  });

  @override
  State<_PodButton> createState() => _PodButtonState();
}

class _PodButtonState extends State<_PodButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final fgColor =
        widget.isActive
            ? AppTheme.brandPurple
            : widget.accentColor ??
                (_isHovered ? Colors.white : Colors.white.withValues(alpha: 0.85));

    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.label != null ? 14 : 10,
          ),
          height: 40,
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? Colors.white.withValues(alpha: 0.12)
                    : _isHovered
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: _isHovered ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(widget.icon, color: fgColor, size: 20),
                  ),
                  if (widget.badge != null && widget.badge! > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${widget.badge}',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.1,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label!,
                  style: TextStyle(
                    color:
                        widget.accentColor != null ? Colors.white : fgColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.label == null && widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _isHovered ? 0.7 : 0.45),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: Colors.white.withValues(alpha: _isHovered ? 0.18 : 0.08),
              ),
            ),
            alignment: Alignment.center,
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
