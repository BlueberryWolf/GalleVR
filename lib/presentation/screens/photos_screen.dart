import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/photos_controller.dart';
import 'photos/widgets/photo_grid_item.dart';
import 'photos/widgets/photo_detail_view.dart';
import 'photos/photos_utils.dart';
import '../../data/models/photo_metadata.dart';
import 'mass_upload_screen.dart';

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
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      cacheExtent:
                          0, // Force aggressive disposal of off-screen items to save RAM
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
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: hasSelection ? 24 : -100,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1B26).withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selections Count Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.15),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withOpacity(0.2),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          count == 1 ? 'photo selected' : 'photos selected',
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Container(
                    height: 24,
                    width: 1,
                    color: Colors.white.withOpacity(0.1),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),

                  // Actions
                  ElevatedButton.icon(
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
                    label: const Text('UPLOAD'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF3B82F6,
                      ).withOpacity(0.15),
                      foregroundColor: const Color(0xFF60A5FA),
                      disabledBackgroundColor: Colors.white.withOpacity(0.05),
                      disabledForegroundColor: Colors.white24,
                      elevation: 0,
                      side: BorderSide(
                        color:
                            count == 0
                                ? Colors.white.withOpacity(0.1)
                                : const Color(0xFF3B82F6).withOpacity(0.5),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),

                  // Divider
                  Container(
                    height: 24,
                    width: 1,
                    color: Colors.white.withOpacity(0.1),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),

                  // Cancel / Close
                  IconButton(
                    onPressed: () => widget.controller.clearSelection(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: Colors.grey,
                    hoverColor: Colors.white.withOpacity(0.1),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
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
          const Icon(Icons.photo_library, size: 64, color: Colors.grey),
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
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => PhotoDetailView(
              photos: widget.controller.value.allPhotos,
              initialIndex: finalIndex,
              onMetadataUpdated: () => widget.controller.refresh(),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
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
        int crossAxisCount = (width / 350).floor();
        crossAxisCount = crossAxisCount.clamp(1, 6);

        return _ThrottledGrid(
          key: const ValueKey('throttled_photo_grid'),
          crossAxisCount: crossAxisCount,
          state: state,
          onOpenDetails: onOpenDetails,
          onShowOptions: onShowOptions,
        );
      },
    );
  }
}

class _ThrottledGrid extends StatefulWidget {
  final int crossAxisCount;
  final PhotosState state;
  final Function(int) onOpenDetails;
  final Function(FileSystemEntity, PhotoMetadata?) onShowOptions;

  const _ThrottledGrid({
    super.key,
    required this.crossAxisCount,
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
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
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
