import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import '../../data/models/config_model.dart';
import '../../data/models/photo_metadata.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/repositories/photo_metadata_repository.dart';
import '../../data/services/photo_event_service.dart';

class PhotosState {
  final List<FileSystemEntity> allPhotos;
  final List<FileSystemEntity> displayedPhotos;
  final Map<String, PhotoMetadata?> metadataMap;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  PhotosState({
    this.allPhotos = const [],
    this.displayedPhotos = const [],
    this.metadataMap = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  PhotosState copyWith({
    List<FileSystemEntity>? allPhotos,
    List<FileSystemEntity>? displayedPhotos,
    Map<String, PhotoMetadata?>? metadataMap,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return PhotosState(
      allPhotos: allPhotos ?? this.allPhotos,
      displayedPhotos: displayedPhotos ?? this.displayedPhotos,
      metadataMap: metadataMap ?? this.metadataMap,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }
}

class PhotosController extends ValueNotifier<PhotosState> {
  final ConfigRepository _configRepository = ConfigRepository();
  final PhotoMetadataRepository _metadataRepository = PhotoMetadataRepository();
  final PhotoEventService _photoEventService = PhotoEventService();

  StreamSubscription? _photoAddedSub;
  StreamSubscription? _photoUploadedSub;

  int _currentPage = 0;
  static const int _pageSize = 24;
  ConfigModel? _config;
  int _currentLoadId = 0;

  PhotosController() : super(PhotosState(isLoading: true));

  void init() {
    _subscribeToEvents();
    Future.microtask(() => loadConfig());
  }

  @override
  void dispose() {
    _photoAddedSub?.cancel();
    _photoUploadedSub?.cancel();
    super.dispose();
  }

  void _subscribeToEvents() {
    _photoAddedSub = _photoEventService.photoAdded.listen((_) => refresh());
    _photoUploadedSub = _photoEventService.photoUploaded.listen(
      (path) => _refreshMetadata(path),
    );
  }

  Future<void> loadConfig() async {
    value = value.copyWith(isLoading: true);
    try {
      _config = await _configRepository.loadConfig();
      await refresh();
    } catch (e) {
      value = value.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh({bool forceSync = false}) async {
    final loadId = ++_currentLoadId;
    if (_config == null || _config!.photosDirectory.isEmpty) {
      value = value.copyWith(
        isLoading: false,
        allPhotos: [],
        displayedPhotos: [],
      );
      return;
    }

    value = value.copyWith(isLoading: true, error: null);

    try {
      if (forceSync) {
        await _metadataRepository.syncWithBackend(force: true);
      } else {
        await _metadataRepository.syncWithBackend();
      }

      final directory = Directory(_config!.photosDirectory);
      if (!await directory.exists()) {
        value = value.copyWith(
          isLoading: false,
          allPhotos: [],
          displayedPhotos: [],
        );
        return;
      }

      final photos = await _scanDirectoryAsync(directory);

      if (loadId != _currentLoadId) return;

      _currentPage = 0;
      final initialBatch = photos.take(_pageSize).toList();

      value = value.copyWith(
        allPhotos: photos,
        displayedPhotos: initialBatch,
      );
      
      // Always reload metadata for the first batch to update sync status/metadata on refresh
      await _loadMetadataForBatch(initialBatch);

      value = value.copyWith(isLoading: false, isLoadingMore: false);
    } catch (e) {
      if (loadId == _currentLoadId) {
        value = value.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  Future<List<FileSystemEntity>> _scanDirectoryAsync(
    Directory directory,
  ) async {
    final List<File> photos = [];
    final Set<String> knownNonVrcx =
        await _metadataRepository.getNonVrcxFilenames();

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            path.extension(entity.path).toLowerCase() == '.png') {
          final filename = path.basename(entity.path);
          if (!knownNonVrcx.contains(filename)) {
            photos.add(entity);
          }
        }
      }
    } catch (e) {
      developer.log('Error listing directory: $e', name: 'PhotosController');
    }

    if (photos.isEmpty) return [];

    final List<MapEntry<File, DateTime>> photoStats = [];

    const batchSize = 100;
    for (var i = 0; i < photos.length; i += batchSize) {
      final end =
          (i + batchSize < photos.length) ? i + batchSize : photos.length;
      final batch = photos.sublist(i, end);

      final results = await Future.wait(
        batch.map((file) async {
          try {
            final stat = await file.stat();
            return MapEntry(file, stat.modified);
          } catch (e) {
            return MapEntry(file, DateTime(1970));
          }
        }),
      );
      photoStats.addAll(results);
    }

    photoStats.sort((a, b) => b.value.compareTo(a.value));

    return photoStats.map((e) => e.key).toList();
  }

  Future<void> loadMore() async {
    if (value.isLoadingMore ||
        (_currentPage + 1) * _pageSize >= value.allPhotos.length) {
      return;
    }

    value = value.copyWith(isLoadingMore: true);
    _currentPage++;

    final start = _currentPage * _pageSize;
    final end =
        (start + _pageSize < value.allPhotos.length)
            ? start + _pageSize
            : value.allPhotos.length;

    final nextBatch = value.allPhotos.sublist(start, end);

    final newDisplayed = List<FileSystemEntity>.from(value.displayedPhotos)
      ..addAll(nextBatch);

    value = value.copyWith(displayedPhotos: newDisplayed, isLoadingMore: false);

    _loadMetadataForBatch(nextBatch);
  }

  Future<void> _loadMetadataForBatch(List<FileSystemEntity> batch) async {
    final paths = batch.map((e) => e.path).toList();
    final metadata = await _metadataRepository.getMetadataForFiles(paths);

    final List<String> badPaths = [];
    metadata.forEach((filePath, meta) {
      if (meta == null ||
          (meta.isNonVrcx && meta.galleryUrl == null) ||
          (meta.galleryUrl == null && meta.world == null && meta.players.isEmpty)) {
        badPaths.add(filePath);
      }
    });

    final newMetadataMap = Map<String, PhotoMetadata?>.from(value.metadataMap);
    newMetadataMap.addAll(metadata);

    if (badPaths.isNotEmpty) {
      final Set<String> badSet = badPaths.toSet();
      final newAllPhotos =
          value.allPhotos.where((e) => !badSet.contains(e.path)).toList();
      final newDisplayedPhotos =
          value.displayedPhotos.where((e) => !badSet.contains(e.path)).toList();

      value = value.copyWith(
        allPhotos: newAllPhotos,
        displayedPhotos: newDisplayedPhotos,
        metadataMap: newMetadataMap,
      );
    } else {
      value = value.copyWith(metadataMap: newMetadataMap);
    }
  }

  Future<void> _refreshMetadata(String filePath) async {
    final metadata = await _metadataRepository.getPhotoMetadataForFile(
      filePath,
    );
    final newMetadataMap = Map<String, PhotoMetadata?>.from(value.metadataMap);
    newMetadataMap[filePath] = metadata;
    value = value.copyWith(metadataMap: newMetadataMap);
  }
}
