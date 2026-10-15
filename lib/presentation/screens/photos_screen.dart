import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../controllers/photos_controller.dart';
import 'photos/widgets/photo_grid_item.dart';
import 'photos/widgets/photo_detail_view.dart';
import 'photos/photos_utils.dart';
import '../../core/image/image_cache_service.dart';
import '../../data/models/photo_metadata.dart';
import 'mass_upload_screen.dart';
import '../theme/app_theme.dart';

class PhotosScreen extends StatefulWidget {
  final PhotosController controller;
  const PhotosScreen({super.key, required this.controller});

  @override
  State<PhotosScreen> createState() => PhotosScreenState();
}

class PhotosScreenState extends State<PhotosScreen> {
  final ScrollController _scrollController = ScrollController();
  int? _lastSelectedIndex;

  @override
  void initState() {
    super.initState();
    widget.controller.init();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 800) {
      widget.controller.loadMore();
    }
  }

  void refresh() {
    widget.controller.refresh();
  }

  void _handlePhotoTap(int index, FileSystemEntity photo) {
    final isCtrlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    final metadata = widget.controller.value.metadataMap[photo.path];
    final isUploaded = metadata?.galleryUrl != null;

    if (widget.controller.value.isSelectionMode ||
        isCtrlPressed ||
        isShiftPressed) {
      if (isUploaded) return;

      if (isShiftPressed && _lastSelectedIndex != null) {
        final start = index < _lastSelectedIndex! ? index : _lastSelectedIndex!;
        final end = index > _lastSelectedIndex! ? index : _lastSelectedIndex!;
        widget.controller.selectPhotosRange(start, end);
      } else {
        widget.controller.togglePhotoSelection(photo.path);
      }
      _lastSelectedIndex = index;
    } else {
      _openPhotoDetails(index);
      _lastSelectedIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ValueListenableBuilder<PhotosState>(
        valueListenable: widget.controller,
        builder: (context, state, child) {
          if (state.allPhotos.isEmpty && !state.isLoading) {
            return _buildEmptyState();
          }

          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.maxScrollExtent < 200 &&
                          state.allPhotos.length >
                              state.displayedPhotos.length &&
                          !state.isLoadingMore) {
                        widget.controller.loadMore();
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      scrollCacheExtent: const ScrollCacheExtent.pixels(0.0),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      key: const PageStorageKey('photos_grid_scroll'),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: _PhotoGridView(
                            state: state,
                            onOpenDetails: (index) {
                              final photo = state.displayedPhotos[index];
                              _handlePhotoTap(index, photo);
                            },
                            onShowOptions: _showPhotoOptions,
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
                ),
              ),
              _buildSelectionBar(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar(PhotosState state) {
    final hasSelection = state.selectedPhotoPaths.isNotEmpty;
    final count = state.selectedPhotoPaths.length;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: const Cubic(0.16, 1, 0.3, 1),
      left: 0,
      right: 0,
      bottom: hasSelection ? 24 : -100,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: hasSelection ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBase,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.cardBorderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xBF000000),
                  blurRadius: 40,
                  spreadRadius: -12,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                const Icon(
                  Icons.library_add_check_rounded,
                  size: 18,
                  color: AppTheme.brandPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  count == 1 ? 'photo selected' : 'photos selected',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 24,
                  color: AppTheme.cardBorderColor,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed:
                        count == 0
                            ? null
                            : () {
                              final paths = state.selectedPhotoPaths.toList();
                              widget.controller.clearSelection();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (context) => MassUploadScreen(
                                        initialFilePaths: paths,
                                        isManualUpload: true,
                                      ),
                                ),
                              );
                            },
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Upload'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => widget.controller.clearSelection(),
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(40, 40),
                    foregroundColor: AppTheme.secondaryTextColor,
                    hoverColor: AppTheme.buttonHoverColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_library,
            size: 64,
            color: AppTheme.secondaryTextColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No photos found',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Take some photos in VRChat to see them here',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => widget.controller.refresh(forceSync: true),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  void _openPhotoDetails(int index) {
    final displayedPhoto = widget.controller.value.displayedPhotos[index];
    final allIndex = widget.controller.value.allPhotos.indexOf(displayedPhoto);
    final finalIndex = allIndex != -1 ? allIndex : 0;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => PhotoDetailView(
              photos: widget.controller.value.allPhotos,
              initialIndex: finalIndex,
              onMetadataUpdated: () => widget.controller.refresh(),
            ),
      ),
    );
  }

  void _showPhotoOptions(FileSystemEntity photo, PhotoMetadata? metadata) {
    showStyledBottomSheet(
      context: context,
      builder:
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('View Photo Info'),
                onTap: () {
                  Navigator.pop(context);
                  _openPhotoDetails(
                    widget.controller.value.displayedPhotos.indexOf(photo),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Show in File Explorer'),
                onTap: () {
                  Navigator.pop(context);
                  showFileInExplorer(photo.path, context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Photo Path'),
                onTap: () {
                  Navigator.pop(context);
                  copyToClipboard(
                    text: photo.path,
                    context: context,
                    successMessage: 'Path copied',
                  );
                },
              ),
            ],
          ),
    );
  }
}

class _PhotoGridView extends StatelessWidget {
  final PhotosState state;
  final Function(int) onOpenDetails;
  final Function(FileSystemEntity, PhotoMetadata?) onShowOptions;

  const _PhotoGridView({
    required this.state,
    required this.onOpenDetails,
    required this.onShowOptions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final crossAxisCount = (width / 350).floor().clamp(1, 6);
        final tileWidth =
            (width - _gridSpacing * (crossAxisCount - 1)) / crossAxisCount;
        final tileHeight = tileWidth / _tileAspectRatio;
        final visibleRows =
            (constraints.viewportMainAxisExtent / (tileHeight + _gridSpacing))
                .ceil() +
            1;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final decodeWidth = ((tileWidth * dpr / 64).ceil() * 64).clamp(
          64,
          2048,
        );
        ImageCacheService.fitToVisible(
          count: visibleRows * crossAxisCount,
          bytesPerImage: decodeWidth * (decodeWidth / _tileAspectRatio) * 4,
        );

        return _ThrottledGrid(
          key: const ValueKey('throttled_photo_grid'),
          crossAxisCount: crossAxisCount,
          decodeWidth: decodeWidth,
          state: state,
          onOpenDetails: onOpenDetails,
          onShowOptions: onShowOptions,
        );
      },
    );
  }
}

const double _gridSpacing = 12;
const double _tileAspectRatio = 16 / 9;

class _ThrottledGrid extends StatefulWidget {
  final int crossAxisCount;
  final int decodeWidth;
  final PhotosState state;
  final Function(int) onOpenDetails;
  final Function(FileSystemEntity, PhotoMetadata?) onShowOptions;

  const _ThrottledGrid({
    super.key,
    required this.crossAxisCount,
    required this.decodeWidth,
    required this.state,
    required this.onOpenDetails,
    required this.onShowOptions,
  });

  @override
  State<_ThrottledGrid> createState() => _ThrottledGridState();
}

class _ThrottledGridState extends State<_ThrottledGrid> {
  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: _tileAspectRatio,
        crossAxisSpacing: _gridSpacing,
        mainAxisSpacing: _gridSpacing,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // loading skeletons
          if (widget.state.isLoading && widget.state.displayedPhotos.isEmpty) {
            return PhotoGridItem.skeleton();
          }

          if (index >= widget.state.displayedPhotos.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                ),
              ),
            );
          }

          final photo = widget.state.displayedPhotos[index];
          final metadata = widget.state.metadataMap[photo.path];
          final isSelected = widget.state.selectedPhotoPaths.contains(
            photo.path,
          );
          final isSelectionMode = widget.state.isSelectionMode;

          return PhotoGridItem(
            key: ValueKey(photo.path),
            entity: photo,
            metadata: metadata,
            onTap: () => widget.onOpenDetails(index),
            onOptionsPressed: () => widget.onShowOptions(photo, metadata),
            isSelected: isSelected,
            isSelectionMode: isSelectionMode,
            decodeWidth: widget.decodeWidth,
          );
        },
        childCount:
            (widget.state.isLoading && widget.state.displayedPhotos.isEmpty)
                ? 12
                : widget.state.displayedPhotos.length +
                    (widget.state.isLoadingMore ? 1 : 0),
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}
