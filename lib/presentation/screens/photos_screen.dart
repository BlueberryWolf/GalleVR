import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../data/repositories/config_repository.dart';
import '../../data/models/config_model.dart';
import '../../data/models/photo_metadata.dart';
import '../../data/repositories/photo_metadata_repository.dart';
import '../../data/services/photo_event_service.dart';
import '../../core/image/image_cache_service.dart';
import '../../core/image/thumbnail_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/photo_metadata_panel.dart';
import '../widgets/cached_image.dart';

class _PhotoScanParams {
  final String directoryPath;
  final String fileExtension;

  _PhotoScanParams({required this.directoryPath, required this.fileExtension});
}

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  final ConfigRepository _configRepository = ConfigRepository();
  final PhotoEventService _photoEventService = PhotoEventService();
  ConfigModel? _config;

  List<FileSystemEntity> _allPhotos = [];
  List<FileSystemEntity> _displayedPhotos = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();

  StreamSubscription<String>? _photoAddedSubscription;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_scrollListener);

    _configureImageCacheSettings();


    _loadConfig();
    _subscribeToPhotoEvents();
  }

  void _configureImageCacheSettings() {
    // Set balanced image cache limits for good performance and loading
    PaintingBinding.instance.imageCache.maximumSize = 100; // Reasonable cache size
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        20 * 1024 * 1024; // 20MB limit

    developer.log(
      'Configured balanced image cache limits: 100 images, 20MB max',
      name: 'PhotosScreen',
    );
  }

  @override
  void dispose() {
    _photoAddedSubscription?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();

    // Clear image caches to prevent memory leaks
    _clearImageCaches();

    super.dispose();
  }

  void _clearImageCaches() {
    try {
      // Clear Flutter's image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Clear thumbnail provider cache
      final thumbnailProvider = ThumbnailProvider();
      thumbnailProvider.clearThumbnails();

      developer.log('Cleared image caches on dispose', name: 'PhotosScreen');
    } catch (e) {
      developer.log('Error clearing image caches: $e', name: 'PhotosScreen');
    }
  }

  void _scrollListener() {
    // Only load more photos when near the end
    if (_scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 1000 &&
        !_isLoadingMore &&
        _displayedPhotos.length < _allPhotos.length) {
      _loadMorePhotos();
    }
    // Removed periodic cache cleanup - it was causing scroll jank
  }

  void _subscribeToPhotoEvents() {
    developer.log('Subscribing to photo events', name: 'PhotosScreen');
    _photoAddedSubscription = _photoEventService.photoAdded.listen((photoPath) {
      developer.log('Photo event received: $photoPath', name: 'PhotosScreen');

      if (_metadataCache.containsKey(photoPath)) {
        developer.log(
          'Clearing metadata cache for: $photoPath',
          name: 'PhotosScreen',
        );
        _metadataCache.remove(photoPath);
      }

      if (mounted) {
        developer.log('Refreshing photos list', name: 'PhotosScreen');
        _loadPhotos();
      }
    });
  }

  Future<void> _loadConfig() async {
    developer.log('Loading config...', name: 'PhotosScreen');
    setState(() {
      _isLoading = true;
    });

    try {
      final config = await _configRepository.loadConfig();
      developer.log(
        'Config loaded, photos directory: ${config.photosDirectory}',
        name: 'PhotosScreen',
      );
      setState(() {
        _config = config;
      });

      await _loadPhotos();
    } catch (e) {
      developer.log('Error loading config: $e', name: 'PhotosScreen', error: e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
    developer.log('Loading photos...', name: 'PhotosScreen');
    if (_config == null || _config!.photosDirectory.isEmpty) {
      developer.log('No photos directory set', name: 'PhotosScreen');
      setState(() {
        _allPhotos = [];
        _displayedPhotos = [];
        _currentPage = 0;
      });
      return;
    }

    try {
      final directory = Directory(_config!.photosDirectory);
      if (!await directory.exists()) {
        developer.log(
          'Photos directory does not exist: ${_config!.photosDirectory}',
          name: 'PhotosScreen',
        );
        setState(() {
          _allPhotos = [];
          _displayedPhotos = [];
          _currentPage = 0;
        });
        return;
      }

      developer.log(
        'Scanning directory: ${_config!.photosDirectory}',
        name: 'PhotosScreen',
      );

      final photos = await compute(
        _findPhotosInDirectory,
        _PhotoScanParams(
          directoryPath: _config!.photosDirectory,
          fileExtension: '.png',
        ),
      );

      developer.log('Found ${photos.length} photos', name: 'PhotosScreen');

      _metadataCache.clear();
      developer.log('Metadata cache cleared', name: 'PhotosScreen');

      setState(() {
        _allPhotos = photos;
        _displayedPhotos = [];
        _currentPage = 0;
      });

      _loadMorePhotos();
    } catch (e) {
      developer.log('Error loading photos: $e', name: 'PhotosScreen', error: e);
      setState(() {
        _allPhotos = [];
        _displayedPhotos = [];
        _currentPage = 0;
      });
    }
  }

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || _currentPage * _pageSize >= _allPhotos.length) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final start = _currentPage * _pageSize;
      final end =
          (start + _pageSize < _allPhotos.length)
              ? start + _pageSize
              : _allPhotos.length;

      final nextPagePhotos = _allPhotos.sublist(start, end);


      if (!mounted) return;

      setState(() {
        _displayedPhotos.addAll(nextPagePhotos);
        _currentPage++;
        _isLoadingMore = false;
      });

      developer.log(
        'Loaded more photos: ${_displayedPhotos.length}/${_allPhotos.length}',
        name: 'PhotosScreen',
      );
    } catch (e) {
      developer.log('Error loading more photos: $e', name: 'PhotosScreen');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  static List<FileSystemEntity> _findPhotosInDirectory(
    _PhotoScanParams params,
  ) {
    final directory = Directory(params.directoryPath);
    if (!directory.existsSync()) {
      return [];
    }

    final entities = directory.listSync(recursive: true);

    final photos =
        entities.where((entity) {
          if (entity is! File) return false;
          final extension = path.extension(entity.path).toLowerCase();
          return extension == params.fileExtension.toLowerCase();
        }).toList();

    photos.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return bTime.compareTo(aTime);
    });

    return photos;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allPhotos.isEmpty) {
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
            Text(
              _config?.photosDirectory.isEmpty == true
                  ? 'Please set a photos directory in settings'
                  : 'Take some photos in VRChat to see them here',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPhotos,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadPhotos,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPhotos,
            color: AppTheme.primaryColor,
            backgroundColor: AppTheme.surfaceColor,
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                childAspectRatio: 16 / 9,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              cacheExtent: 500,
              itemCount:
                  _displayedPhotos.length +
                  (_isLoadingMore || _displayedPhotos.length < _allPhotos.length
                      ? 1
                      : 0),
              itemBuilder: (context, index) {
                if (index >= _displayedPhotos.length) {
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

                final photo = _displayedPhotos[index];
                return _buildPhotoItem(photo);
              },
            ),
          ),
        ),
      ],
    );
  }

  final Map<String, Future<PhotoMetadata?>> _metadataCache = {};

  Future<PhotoMetadata?> _getMetadataFuture(
    String filePath, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh || !_metadataCache.containsKey(filePath)) {
      developer.log(
        'Getting fresh metadata for: $filePath',
        name: 'PhotosScreen',
      );
      _metadataCache[filePath] = PhotoMetadataRepository()
          .getPhotoMetadataForFile(filePath);
    }
    return _metadataCache[filePath]!;
  }

  Widget _buildPhotoItem(FileSystemEntity entity) {
    return FutureBuilder<PhotoMetadata?>(
      future: _getMetadataFuture(entity.path),
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        final hasWorld = metadata?.world != null;
        final hasPlayers = metadata?.players.isNotEmpty == true;

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          margin: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openPhotoDetails(entity),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPhotoImage(entity),

                  // Bottom overlay with filename
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withAlpha(120)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          metadata?.filename ?? path.basename(entity.path),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),

                  // Metadata indicators
                  if (hasWorld || hasPlayers)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasWorld)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.public,
                                color: Colors.white,
                                size: 8,
                              ),
                            ),
                          if (hasWorld && hasPlayers) const SizedBox(width: 2),
                          if (hasPlayers)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.people,
                                color: Colors.white,
                                size: 8,
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Options button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(100),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.more_vert, size: 12),
                        color: Colors.white,
                        onPressed: () => _showPhotoOptions(entity),
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoImage(FileSystemEntity entity) {
    return CachedImage(
      filePath: entity.path,
      fit: BoxFit.cover,
      thumbnailSize: 400, // Increased slightly for better loading reliability
      highQuality: false,
    );
  }

  void _showPhotoOptions(FileSystemEntity entity) {
    showStyledBottomSheet(
      context: context,
      builder:
          (context) => FutureBuilder<PhotoMetadata?>(
            future: _getMetadataFuture(entity.path),
            builder: (context, snapshot) {
              final metadata = snapshot.data;
              final hasMetadata =
                  metadata != null &&
                  (metadata.world != null || metadata.players.isNotEmpty);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('View Photo Info'),
                    subtitle:
                        hasMetadata
                            ? const Text(
                              'World and player information available',
                            )
                            : const Text('Basic photo information'),
                    onTap: () {
                      Navigator.pop(context);
                      _openPhotoDetails(entity);
                    },
                  ),
                  if (metadata?.players.isNotEmpty == true)
                    ListTile(
                      leading: const Icon(Icons.people_alt_rounded),
                      title: Text('Players (${metadata!.players.length})'),
                      subtitle: Text(
                        metadata.players.length > 3
                            ? '${metadata.players.take(3).map((p) => p.name).join(', ')}...'
                            : metadata.players.map((p) => p.name).join(', '),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _openPhotoDetails(entity);
                      },
                    ),
                  if (metadata?.world != null)
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('World'),
                      subtitle: Text(metadata!.world!.name),
                      onTap: () {
                        Navigator.pop(context);
                        _openPhotoDetails(entity);
                      },
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copy Photo Link'),
                    onTap: () async {
                      Navigator.pop(context);
                      final metadata = snapshot.data;

                      if (metadata?.galleryUrl != null) {
                        await copyToClipboard(
                          text: metadata!.galleryUrl!,
                          context: context,
                          successMessage: 'Gallery link copied to clipboard',
                          loggerName: 'PhotosScreen',
                        );
                      } else {
                        await copyToClipboard(
                          text: entity.path,
                          context: context,
                          successMessage:
                              'Photo path copied to clipboard (no gallery link available)',
                          loggerName: 'PhotosScreen',
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Show in File Explorer'),
                    onTap: () {
                      Navigator.pop(context);
                      showFileInExplorer(entity.path, context);
                    },
                  ),
                ],
              );
            },
          ),
    );
  }

  void _openPhotoDetails(FileSystemEntity entity) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                _PhotoDetailScreen(entity: entity, allPhotos: _displayedPhotos),
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }
}

class _PhotoDetailScreen extends StatefulWidget {
  final FileSystemEntity entity;

  final List<FileSystemEntity>? allPhotos;

  const _PhotoDetailScreen({required this.entity, this.allPhotos});

  @override
  State<_PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<_PhotoDetailScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final PhotoMetadataRepository _metadataRepository = PhotoMetadataRepository();
  PhotoMetadata? _metadata;
  bool _isMetadataPanelOpen = false;
  bool _isLoading = true;

  final FocusNode _focusNode = FocusNode();

  int _currentIndex = 0;

  final GlobalKey _imageKey = GlobalKey();

  late AnimationController _indicatorController;
  bool _showNavigationIndicators = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    if (widget.allPhotos != null) {
      _currentIndex = widget.allPhotos!.indexWhere(
        (photo) => photo.path == widget.entity.path,
      );
    }

    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    Future.delayed(const Duration(milliseconds: 300), _loadMetadata);

    _showIndicators();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      developer.log(
        'Loading metadata for file: ${widget.entity.path}',
        name: 'PhotoDetailScreen',
      );

      final parentState = context.findAncestorStateOfType<_PhotosScreenState>();
      if (parentState != null) {
        final fileStats = widget.entity.statSync();
        final fileModTime = fileStats.modified;
        final currentTime = DateTime.now();
        final timeDifference = currentTime.difference(fileModTime);

        final bool isRecentlyAdded = timeDifference.inMinutes < 1;

        if (isRecentlyAdded) {
          developer.log(
            'Recently added photo detected, forcing metadata refresh',
            name: 'PhotoDetailScreen',
          );
        }

        final metadata = await parentState._getMetadataFuture(
          widget.entity.path,
          forceRefresh: isRecentlyAdded,
        );

        if (mounted) {
          setState(() {
            _metadata = metadata;
            _isLoading = false;
          });
        }
        return;
      }

      final metadata = await _metadataRepository.getPhotoMetadataForFile(
        widget.entity.path,
      );

      if (metadata != null) {
        developer.log(
          'Metadata found: ${metadata.filename}',
          name: 'PhotoDetailScreen',
        );
      } else {
        developer.log('No metadata found for file', name: 'PhotoDetailScreen');
      }

      if (mounted) {
        setState(() {
          _metadata = metadata;
        });
      }
    } catch (e) {
      developer.log(
        'Error loading metadata: $e',
        name: 'PhotoDetailScreen',
        error: e,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleMetadataPanel() {
    setState(() {
      _isMetadataPanelOpen = !_isMetadataPanelOpen;
    });
  }

  void _navigateToNext() {
    developer.log(
      'Attempting to navigate to next photo, current index: $_currentIndex, total photos: ${widget.allPhotos?.length}',
      name: 'PhotoDetailScreen',
    );

    if (widget.allPhotos == null) {
      developer.log(
        'Cannot navigate: allPhotos is null',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    if (_currentIndex >= widget.allPhotos!.length - 1) {
      developer.log(
        'Cannot navigate: already at last photo',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    developer.log(
      'Navigating to next photo at index: ${_currentIndex + 1}',
      name: 'PhotoDetailScreen',
    );
    _navigateToPhoto(_currentIndex + 1);
  }

  void _navigateToPrevious() {
    developer.log(
      'Attempting to navigate to previous photo, current index: $_currentIndex',
      name: 'PhotoDetailScreen',
    );

    if (widget.allPhotos == null) {
      developer.log(
        'Cannot navigate: allPhotos is null',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    if (_currentIndex <= 0) {
      developer.log(
        'Cannot navigate: already at first photo',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    developer.log(
      'Navigating to previous photo at index: ${_currentIndex - 1}',
      name: 'PhotoDetailScreen',
    );
    _navigateToPhoto(_currentIndex - 1);
  }

  void _navigateToPhoto(int index) {
    developer.log(
      '_navigateToPhoto called with index: $index',
      name: 'PhotoDetailScreen',
    );

    if (widget.allPhotos == null) {
      developer.log(
        'Cannot navigate: allPhotos is null',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    if (index < 0 || index >= widget.allPhotos!.length) {
      developer.log(
        'Cannot navigate: index out of bounds',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    if (index == _currentIndex) {
      developer.log(
        'Cannot navigate: already at requested index',
        name: 'PhotoDetailScreen',
      );
      return;
    }

    final targetPhoto = widget.allPhotos![index];
    developer.log(
      'Target photo path: ${targetPhoto.path}',
      name: 'PhotoDetailScreen',
    );

    _directNavigateToPhoto(targetPhoto);
  }

  void _directNavigateToPhoto(FileSystemEntity targetPhoto) {
    developer.log(
      'Direct navigating to photo: ${targetPhoto.path}',
      name: 'PhotoDetailScreen',
    );

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => _PhotoDetailScreen(
              entity: targetPhoto,
              allPhotos: widget.allPhotos,
            ),
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  void _showIndicators() {
    setState(() {
      _showNavigationIndicators = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showNavigationIndicators = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasMetadata =
        _metadata != null &&
        (_metadata!.world != null || _metadata!.players.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(100),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (hasMetadata)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      _isMetadataPanelOpen
                          ? AppTheme.primaryColor.withAlpha(150)
                          : Colors.black.withAlpha(100),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.people_alt_rounded, color: Colors.white),
                    if (_metadata?.players.isNotEmpty == true)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_metadata!.players.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              onPressed: _toggleMetadataPanel,
              tooltip: 'Show metadata',
            ),
          if (_metadata?.galleryUrl != null)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(100),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share_rounded, color: Colors.white),
              ),
              onPressed: () async {
                if (_metadata?.galleryUrl != null) {
                  await copyToClipboard(
                    text: _metadata!.galleryUrl!,
                    context: context,
                    successMessage: 'Gallery URL copied to clipboard',
                    loggerName: 'PhotoDetailScreen',
                    onSuccess: _openInGallery,
                  );
                }
              },
              tooltip: 'Copy gallery link',
            ),
          // Copy image button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(100),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.copy, color: Colors.white),
            ),
            onPressed: _copyImageToClipboard,
            tooltip: 'Copy image to clipboard',
          ),
          // Show in file explorer button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(100),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open, color: Colors.white),
            ),
            onPressed: _showInFileExplorer,
            tooltip: 'Show in File Explorer',
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(100),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.more_vert_rounded, color: Colors.white),
            ),
            onPressed: () {
              showStyledBottomSheet(
                context: context,
                builder:
                    (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('Properties'),
                          onTap: () {
                            Navigator.pop(context);
                            _toggleMetadataPanel();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.share_rounded),
                          title: const Text('Copy Gallery Link'),
                          onTap: () {
                            Navigator.pop(context);
                            _copyPhotoLinkToClipboard();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.copy),
                          title: const Text('Copy Image to Clipboard'),
                          onTap: () {
                            Navigator.pop(context);
                            _copyImageToClipboard();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: const Text('Show in File Explorer'),
                          onTap: () {
                            Navigator.pop(context);
                            _showInFileExplorer();
                          },
                        ),
                      ],
                    ),
              );
            },
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          developer.log(
            'Key event received: ${event.logicalKey}',
            name: 'PhotoDetailScreen',
          );

          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              developer.log(
                'Right arrow key pressed',
                name: 'PhotoDetailScreen',
              );
              _navigateToNext();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              developer.log(
                'Left arrow key pressed',
                name: 'PhotoDetailScreen',
              );
              _navigateToPrevious();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              developer.log('Escape key pressed', name: 'PhotoDetailScreen');
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () {
            _showIndicators();
          },

          onTapDown: (details) {
            final size = MediaQuery.of(context).size;
            final tapX = details.globalPosition.dx;
            final tapY = details.globalPosition.dy;

            final centerX = size.width / 2;
            final centerY = size.height / 2;
            final centerWidth = size.width * 0.7;
            final centerHeight = size.height * 0.7;

            final isOutsideX =
                tapX < centerX - centerWidth / 2 ||
                tapX > centerX + centerWidth / 2;
            final isOutsideY =
                tapY < centerY - centerHeight / 2 ||
                tapY > centerY + centerHeight / 2;

            if (isOutsideX || isOutsideY) {
              Navigator.of(context).pop();
            }
          },
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;

            final bool canNavigatePrevious =
                widget.allPhotos != null && _currentIndex > 0;
            final bool canNavigateNext =
                widget.allPhotos != null &&
                _currentIndex < widget.allPhotos!.length - 1;

            if (details.primaryVelocity! > 300 && canNavigatePrevious) {
              _navigateToPrevious();
            } else if (details.primaryVelocity! < -300 && canNavigateNext) {
              _navigateToNext();
            }

            _showIndicators();
          },
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  child: Hero(
                    tag: widget.entity.path,
                    createRectTween: (begin, end) {
                      return RectTween(begin: begin, end: end);
                    },
                    flightShuttleBuilder: (
                      BuildContext flightContext,
                      Animation<double> animation,
                      HeroFlightDirection flightDirection,
                      BuildContext fromHeroContext,
                      BuildContext toHeroContext,
                    ) {
                      return Material(
                        color: Colors.transparent,
                        child: CachedImage(
                          filePath: widget.entity.path,
                          fit: BoxFit.contain,
                          highQuality: false,
                        ),
                      );
                    },
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: RepaintBoundary(
                        key: _imageKey,
                        child: CachedImage(
                          filePath: widget.entity.path,
                          fit: BoxFit.contain,
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.height,
                          thumbnailSize: 800,
                          highQuality: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (_isLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withAlpha(76),
                    child: const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (widget.allPhotos != null && _currentIndex > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: MediaQuery.of(context).size.width * 0.2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        developer.log(
                          'Left navigation area tapped',
                          name: 'PhotoDetailScreen',
                        );
                        _navigateToPrevious();
                      },
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _showNavigationIndicators ? 1.0 : 0.3,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(150),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (widget.allPhotos != null &&
                  _currentIndex < widget.allPhotos!.length - 1)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: MediaQuery.of(context).size.width * 0.2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        developer.log(
                          'Right navigation area tapped',
                          name: 'PhotoDetailScreen',
                        );
                        _navigateToNext();
                      },
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _showNavigationIndicators ? 1.0 : 0.3,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(150),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  offset:
                      _isMetadataPanelOpen ? Offset.zero : const Offset(1, 0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: PhotoMetadataPanel(
                    metadata: _metadata,
                    isOpen: _isMetadataPanelOpen,
                    onClose: _toggleMetadataPanel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black.withAlpha(150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _metadata?.filename ?? path.basename(widget.entity.path),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _metadata != null
                        ? _formatDate(
                          DateTime.fromMillisecondsSinceEpoch(
                            _metadata!.takenDate,
                          ),
                        )
                        : _formatDate(widget.entity.statSync().modified),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_metadata?.galleryUrl != null)
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Open in Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _openInGallery(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInGallery() async {
    if (_metadata?.galleryUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No gallery link available')),
        );
      }
      return;
    }

    await openUrl(
      _metadata!.galleryUrl!,
      context,
      loggerName: 'PhotoDetailScreen',
    );
  }

  Future<void> _copyPhotoLinkToClipboard() async {
    if (_metadata?.galleryUrl != null) {
      final String galleryUrl = _metadata!.galleryUrl!;

      await copyToClipboard(
        text: galleryUrl,
        context: context,
        successMessage: 'Gallery link copied to clipboard',
        loggerName: 'PhotoDetailScreen',
        onSuccess: _openInGallery,
      );
    } else {
      final String fallbackMessage =
          'No gallery link available for this photo.';

      await copyToClipboard(
        text: fallbackMessage,
        context: context,
        successMessage: 'No gallery link available for this photo',
        loggerName: 'PhotoDetailScreen',
      );
    }
  }

  Future<void> _showInFileExplorer() async {
    await showFileInExplorer(widget.entity.path, context);
  }

  Future<void> _copyImageToClipboard() async {
    try {
      final filePath = widget.entity.path;
      final file = File(filePath);

      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Image file not found')));
        }
        return;
      }

      final result = await Pasteboard.writeFiles([filePath]);

      if (mounted) {
        if (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image copied to clipboard')),
          );

          developer.log(
            'Copied image to clipboard: $filePath',
            name: 'PhotoDetailScreen',
          );
        } else {
          // Try an alternative method if the first one failed
          try {
            // Try to use the image data directly
            final bytes = await File(filePath).readAsBytes();
            await Pasteboard.writeImage(bytes);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Image copied to clipboard')),
              );

              developer.log(
                'Copied image data to clipboard: $filePath',
                name: 'PhotoDetailScreen',
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to copy image to clipboard: $e'),
                ),
              );
            }

            developer.log(
              'Error copying image data to clipboard: $e',
              name: 'PhotoDetailScreen',
              error: e,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error copying image: $e')));
      }

      developer.log(
        'Error copying image to clipboard: $e',
        name: 'PhotoDetailScreen',
        error: e,
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Utility function to copy text to clipboard and show a snackbar
Future<void> copyToClipboard({
  required String text,
  required BuildContext context,
  required String successMessage,
  String? fallbackText,
  String? fallbackMessage,
  String loggerName = 'ClipboardUtil',
  VoidCallback? onSuccess,
}) async {
  final bool isContextMounted = context.mounted;

  try {
    await Clipboard.setData(ClipboardData(text: text));

    if (isContextMounted && context.mounted) {
      final snackBar = SnackBar(
        content: Text(successMessage),
        action:
            onSuccess != null
                ? SnackBarAction(label: 'Open', onPressed: onSuccess)
                : null,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }

    developer.log('Copied to clipboard: $text', name: loggerName);
  } catch (e) {
    if (fallbackText != null) {
      try {
        await Clipboard.setData(ClipboardData(text: fallbackText));

        if (isContextMounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fallbackMessage ?? 'Fallback text copied to clipboard',
              ),
            ),
          );
        }

        developer.log(
          'Copied fallback text to clipboard: $fallbackText',
          name: loggerName,
        );
      } catch (e) {
        if (isContextMounted && context.mounted) {
          _handleClipboardError(e, context, loggerName);
        } else {
          _handleClipboardError(e, null, loggerName);
        }
      }
    } else {
      if (isContextMounted && context.mounted) {
        _handleClipboardError(e, context, loggerName);
      } else {
        _handleClipboardError(e, null, loggerName);
      }
    }
  }
}

/// Helper function to handle clipboard errors
void _handleClipboardError(
  dynamic error,
  BuildContext? context,
  String loggerName,
) {
  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error copying to clipboard: $error')),
    );
  }

  developer.log(
    'Error copying to clipboard: $error',
    name: loggerName,
    error: error,
  );
}

/// Shows a modal bottom sheet with consistent styling
void showStyledBottomSheet({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// Utility function to open a URL in the default browser
Future<void> openUrl(
  String url,
  BuildContext context, {
  String loggerName = 'UrlOpener',
}) async {
  try {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);

      developer.log('Opened URL: $url', name: loggerName);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
      }

      developer.log('Could not launch URL: $url', name: loggerName);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error opening URL: $e')));
    }

    developer.log('Error opening URL: $e', name: loggerName, error: e);
  }
}

/// Utility function to show a file in the system's file explorer
Future<void> showFileInExplorer(String filePath, BuildContext context) async {
  try {
    final uri = Uri.parse('file:${filePath.replaceAll('\\', '/')}');

    if (Platform.isWindows) {
      await Process.run('explorer.exe', [
        '/select,$filePath',
      ], runInShell: true);

      // Note: explorer.exe often returns exit code 1 even when successful,
      // so we don't check the exit code here
      developer.log(
        'Opened file explorer and selected file: $filePath',
        name: 'FileExplorerUtil',
      );
    } else if (await canLaunchUrl(uri)) {
      final directoryPath = path.dirname(filePath);
      final directoryUri = Uri.parse('file:$directoryPath');
      await launchUrl(directoryUri);

      developer.log(
        'Opened file explorer at: $directoryPath',
        name: 'FileExplorerUtil',
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file explorer')),
        );
      }

      developer.log(
        'Could not open file explorer for path: $filePath',
        name: 'FileExplorerUtil',
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file explorer: $e')),
      );
    }

    developer.log(
      'Error opening file explorer: $e',
      name: 'FileExplorerUtil',
      error: e,
    );
  }
}