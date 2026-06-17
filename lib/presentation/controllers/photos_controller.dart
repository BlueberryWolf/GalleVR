import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;
import '../../data/models/config_model.dart';
import '../../data/models/photo_metadata.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/repositories/photo_metadata_repository.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/photo_event_service.dart';
import '../../data/services/vrchat_service.dart';

class PhotosState {
  final List<FileSystemEntity> allPhotos;
  final List<FileSystemEntity> displayedPhotos;
  final Map<String, PhotoMetadata?> metadataMap;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final Set<String> selectedPhotoPaths;
  final bool isSelectionMode;

  PhotosState({
    this.allPhotos = const [],
    this.displayedPhotos = const [],
    this.metadataMap = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.selectedPhotoPaths = const {},
    this.isSelectionMode = false,
  });

  PhotosState copyWith({
    List<FileSystemEntity>? allPhotos,
    List<FileSystemEntity>? displayedPhotos,
    Map<String, PhotoMetadata?>? metadataMap,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    Set<String>? selectedPhotoPaths,
    bool? isSelectionMode,
  }) {
    return PhotosState(
      allPhotos: allPhotos ?? this.allPhotos,
      displayedPhotos: displayedPhotos ?? this.displayedPhotos,
      metadataMap: metadataMap ?? this.metadataMap,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
      selectedPhotoPaths: selectedPhotoPaths ?? this.selectedPhotoPaths,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }
}

class PhotosController extends ValueNotifier<PhotosState> {
  final ConfigRepository _configRepository = ConfigRepository();
  final PhotoMetadataRepository _metadataRepository = PhotoMetadataRepository();
  final PhotoEventService _photoEventService = PhotoEventService();

  StreamSubscription? _photoAddedSub;
  StreamSubscription? _photoUploadedSub;
  StreamSubscription<ConfigModel>? _configSub;
  StreamSubscription? _authSub;

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
    _configSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void _subscribeToEvents() {
    _photoAddedSub = _photoEventService.photoAdded.listen((_) => refresh());
    _photoUploadedSub = _photoEventService.photoUploaded.listen(
      (path) => _refreshMetadata(path),
    );
    _configSub = AppServiceManager().configStream.listen((updatedConfig) {
      _config = updatedConfig;
      refresh();
    });
    _authSub = AppServiceManager().authDataStream.listen((_) {
      refresh();
    });
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
    final authData = AppServiceManager().authData;
    final authDataSec = await VRChatService().loadAuthDataSecondary();

    final hasVRC =
        (authData != null && !authData.userId.startsWith('U-')) ||
        (authDataSec != null && !authDataSec.userId.startsWith('U-'));
    final hasResonite =
        (authData != null && authData.userId.startsWith('U-')) ||
        (authDataSec != null && authDataSec.userId.startsWith('U-'));

    final vrcPhotosDir = hasVRC ? _config?.photosDirectory : null;
    final resonitePhotosDir =
        hasResonite ? _config?.resonitePhotosDirectory : null;

    final hasVrcDir = vrcPhotosDir != null && vrcPhotosDir.isNotEmpty;
    final hasResoniteDir =
        resonitePhotosDir != null && resonitePhotosDir.isNotEmpty;

    if (_config == null || (!hasVrcDir && !hasResoniteDir)) {
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

      final List<FileSystemEntity> allPhotosList = [];

      if (hasVrcDir) {
        final directory = Directory(vrcPhotosDir);
        if (await directory.exists()) {
          final vrcPhotos = await _scanDirectoryAsync(
            directory,
            isResonite: false,
          );
          allPhotosList.addAll(vrcPhotos);
        }
      }

      if (hasResoniteDir) {
        final directory = Directory(resonitePhotosDir);
        if (await directory.exists()) {
          final resonitePhotos = await _scanDirectoryAsync(
            directory,
            isResonite: true,
          );
          allPhotosList.addAll(resonitePhotos);
        }
      }

      // Sort merged photos by modified time
      final List<MapEntry<FileSystemEntity, DateTime>> photoStats = [];
      for (final file in allPhotosList) {
        try {
          final stat = file.statSync();
          photoStats.add(MapEntry(file, stat.modified));
        } catch (e) {
          photoStats.add(MapEntry(file, DateTime(1970)));
        }
      }
      photoStats.sort((a, b) => b.value.compareTo(a.value));
      final sortedPhotos = photoStats.map((e) => e.key).toList();

      if (loadId != _currentLoadId) return;

      _currentPage = 0;
      final initialBatch = sortedPhotos.take(_pageSize).toList();

      value = value.copyWith(
        allPhotos: sortedPhotos,
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
    Directory directory, {
    required bool isResonite,
  }) async {
    final Set<String> knownNonVrcx =
        await _metadataRepository.getNonVrcxFilenames();

    final sortedPaths = await compute(
      _scanDirectoryIsolate,
      ScanParams(directory.path, knownNonVrcx, isResonite: isResonite),
    );

    return sortedPaths.map((p) => File(p)).toList();
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

    final resoniteDir = _config?.resonitePhotosDirectory;
    final List<String> badPaths = [];
    metadata.forEach((filePath, meta) {
      final isResonitePath = resoniteDir != null &&
          resoniteDir.isNotEmpty &&
          path.isWithin(resoniteDir, filePath);
      if (isResonitePath) {
        return;
      }
      if (meta == null ||
          (meta.isNonVrcx && meta.galleryUrl == null) ||
          (meta.application == 'Resonite' &&
              (meta.cameraManufacturer == null ||
                  meta.cameraManufacturer!.isEmpty) &&
              meta.galleryUrl == null)) {
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

  void toggleSelectionMode() {
    final newMode = !value.isSelectionMode;
    value = value.copyWith(
      isSelectionMode: newMode,
      selectedPhotoPaths: newMode ? value.selectedPhotoPaths : const {},
    );
  }

  void togglePhotoSelection(String path) {
    final current = Set<String>.from(value.selectedPhotoPaths);
    if (current.contains(path)) {
      current.remove(path);
    } else {
      current.add(path);
    }
    value = value.copyWith(
      selectedPhotoPaths: current,
      isSelectionMode: current.isNotEmpty ? true : value.isSelectionMode,
    );
  }

  void clearSelection() {
    value = value.copyWith(
      selectedPhotoPaths: const {},
      isSelectionMode: false,
    );
  }

  void selectPhotosRange(int start, int end) {
    final current = Set<String>.from(value.selectedPhotoPaths);
    for (int i = start; i <= end; i++) {
      if (i >= 0 && i < value.displayedPhotos.length) {
        final path = value.displayedPhotos[i].path;
        final meta = value.metadataMap[path];
        if (meta?.galleryUrl == null) {
          current.add(path);
        }
      }
    }
    value = value.copyWith(selectedPhotoPaths: current, isSelectionMode: true);
  }
}

class ScanParams {
  final String directoryPath;
  final Set<String> knownNonVrcx;
  final bool isResonite;

  ScanParams(this.directoryPath, this.knownNonVrcx, {this.isResonite = false});
}

Future<List<String>> _scanDirectoryIsolate(ScanParams params) async {
  final directory = Directory(params.directoryPath);
  if (!directory.existsSync()) return [];

  final List<File> photos = [];
  try {
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        final isAllowed =
            params.isResonite
                ? (ext == '.png' ||
                    ext == '.jpg' ||
                    ext == '.jpeg' ||
                    ext == '.webp')
                : (ext == '.png');
        if (isAllowed) {
          final filename = path.basename(entity.path);
          if (params.isResonite || !params.knownNonVrcx.contains(filename)) {
            photos.add(entity);
          }
        }
      }
    }
  } catch (e) {
    developer.log(
      'Error listing directory in isolate: $e',
      name: 'PhotosController',
    );
  }

  if (photos.isEmpty) return [];

  final List<MapEntry<String, DateTime>> photoStats = [];
  for (final file in photos) {
    try {
      final stat = file.statSync();
      photoStats.add(MapEntry(file.path, stat.modified));
    } catch (e) {
      photoStats.add(MapEntry(file.path, DateTime(1970)));
    }
  }

  photoStats.sort((a, b) => b.value.compareTo(a.value));
  return photoStats.map((e) => e.key).toList();
}
