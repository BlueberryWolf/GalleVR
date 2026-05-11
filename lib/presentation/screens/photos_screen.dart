import 'dart:io';
import 'package:flutter/material.dart';
import '../controllers/photos_controller.dart';
import 'photos/widgets/photo_grid_item.dart';
import 'photos/widgets/photo_detail_view.dart';
import 'photos/photos_utils.dart';
import '../theme/app_theme.dart';
import '../../data/models/photo_metadata.dart';

class PhotosScreen extends StatefulWidget {
  final PhotosController controller;
  const PhotosScreen({super.key, required this.controller});

  @override
  State<PhotosScreen> createState() => PhotosScreenState();
}

class PhotosScreenState extends State<PhotosScreen> {
  final ScrollController _scrollController = ScrollController();

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

          return RepaintBoundary(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                if (notification.metrics.maxScrollExtent < 200 &&
                    state.allPhotos.length > state.displayedPhotos.length &&
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
                      onOpenDetails: _openPhotoDetails,
                      onShowOptions: _showPhotoOptions,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          );
        },
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
            onPressed: widget.controller.refresh,
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

          return PhotoGridItem(
            key: ValueKey(photo.path),
            entity: photo,
            metadata: metadata,
            onTap: () => widget.onOpenDetails(index),
            onOptionsPressed: () => widget.onShowOptions(photo, metadata),
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
