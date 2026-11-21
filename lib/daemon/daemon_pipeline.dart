import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../core/image/image_dimensions_reader.dart';
import '../core/metadata/vrcx_metadata_extractor.dart';
import '../core/utils/log_file_watcher.dart';
import '../core/utils/resonite_dir_watcher.dart';
import '../core/utils/screenshot_utils.dart';
import '../data/models/config_model.dart';
import '../data/models/log_metadata.dart';
import '../data/models/photo_metadata.dart';
import '../data/models/verification_models.dart';
import '../data/services/log_parser_service.dart';
import 'daemon_paths.dart';
import 'daemon_platform.dart';
import 'daemon_storage.dart';

class DaemonPipeline {
  static const String _verifyStatusEndpoint =
      'https://api.gallevr.app/vrchat/verify/status';
  static const String _authMeEndpoint =
      'https://api.gallevr.app/vrchat/auth/me';
  static const String _tosStatusEndpoint =
      'https://api.gallevr.app/vrchat/tos/status';

  final DaemonStorage _storage;
  final DaemonPlatform _platform;
  final void Function(String event, Map<String, dynamic> payload) _emitEvent;
  final LogParserService _logParser = LogParserService();

  ConfigModel? _config;
  LogFileWatcher? _logFileWatcher;
  ResoniteDirWatcher? _resoniteDirWatcher;
  StreamSubscription<String>? _logSub;
  StreamSubscription<String>? _resoniteSub;
  StreamSubscription<FileSystemEvent>? _vrcDirSub;

  final Set<String> _handledPhotos = {};
  final List<Map<String, dynamic>> _eventHistory = [];

  bool _isWatching = false;
  final Map<String, DateTime> _verifiedCache = {};
  final Map<String, DateTime> _tosAcceptedCache = {};

  DaemonPipeline({
    required DaemonStorage storage,
    required DaemonPlatform platform,
    required void Function(String event, Map<String, dynamic> payload) emitEvent,
  }) : _storage = storage,
       _platform = platform,
       _emitEvent = emitEvent;

  bool get isWatching => _isWatching;
  ConfigModel? get config => _config;
  List<Map<String, dynamic>> get history => List.unmodifiable(_eventHistory);

  void _recordEvent(String type, String message, {String? photoPath}) {
    final entry = <String, dynamic>{
      'type': type,
      'message': message,
      if (photoPath != null) 'photoPath': photoPath,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _eventHistory.insert(0, entry);
    if (_eventHistory.length > 100) {
      _eventHistory.removeLast();
    }
    _emitEvent('photoEvent', entry);
  }

  Future<void> reloadConfig() async {
    _verifiedCache.clear();
    _tosAcceptedCache.clear();
    final nextConfig = await _storage.loadConfig();
    final prev = _config;
    _config = nextConfig;

    final dirsChanged =
        prev == null ||
        prev.photosDirectory != nextConfig.photosDirectory ||
        prev.logsDirectory != nextConfig.logsDirectory ||
        prev.resonitePhotosDirectory != nextConfig.resonitePhotosDirectory;

    if (dirsChanged || !_isWatching) {
      await stopWatching();
      await startWatching(nextConfig);
    }

    _platform.trimMemory();
  }

  Future<void> startWatching(ConfigModel config) async {
    _config = config;
    await stopWatching();

    var startedAny = false;

    if (config.resonitePhotosDirectory.isNotEmpty) {
      try {
        _resoniteDirWatcher = ResoniteDirWatcher(config.resonitePhotosDirectory);
        await _resoniteDirWatcher!.startWatching();
        _resoniteSub = _resoniteDirWatcher!.photoStream.listen(
          (photoPath) => _handleResonitePhoto(photoPath),
        );
        startedAny = true;
      } catch (e) {
        _recordEvent('watcher', 'Failed to start Resonite watcher: $e');
      }
    }

    if (config.logsDirectory.isNotEmpty) {
      final logsDir = Directory(config.logsDirectory);
      if (await logsDir.exists()) {
        try {
          _logFileWatcher = LogFileWatcher(config.logsDirectory);
          await _logFileWatcher!.startWatching();
          _logSub = _logFileWatcher!.screenshotStream.listen(
            (screenshotPath) => _handleScreenshotFromLog(screenshotPath),
            onError: (e) => _recordEvent('watcher', 'Log watcher error: $e'),
          );

          if (config.photosDirectory.isNotEmpty) {
            final photosDir = Directory(config.photosDirectory);
            if (await photosDir.exists()) {
              try {
                _vrcDirSub = photosDir
                    .watch(events: FileSystemEvent.create, recursive: true)
                    .listen((_) => _logFileWatcher?.checkForUpdates());
              } catch (_) {}
            }
          }
          startedAny = true;
        } catch (e) {
          _recordEvent('watcher', 'Failed to start VRChat log watcher: $e');
        }
      }
    }

    _isWatching = startedAny;
    _emitEvent('watcherState', {'watching': _isWatching});
  }

  Future<void> stopWatching() async {
    await _resoniteSub?.cancel();
    _resoniteSub = null;
    await _resoniteDirWatcher?.stopWatching();
    _resoniteDirWatcher = null;

    await _vrcDirSub?.cancel();
    _vrcDirSub = null;

    await _logSub?.cancel();
    _logSub = null;
    await _logFileWatcher?.stopWatching();
    _logFileWatcher = null;

    if (_isWatching) {
      _isWatching = false;
      _emitEvent('watcherState', {'watching': false});
    }
  }

  Future<void> _handleResonitePhoto(String photoPath) async {
    if (_handledPhotos.contains(photoPath)) return;
    _rememberHandled(photoPath);

    final file = File(photoPath);
    if (!await _waitForFileStable(file)) return;

    await _processPhoto(photoPath, isResoniteHint: true);
  }

  Future<void> _handleScreenshotFromLog(String screenshotPath) async {
    final config = _config;
    if (config == null) return;

    final resolvedPath = ScreenshotUtils.translatePlatformPath(
      screenshotPath,
      config.photosDirectory,
    );

    if (_handledPhotos.contains(resolvedPath)) return;

    final file = File(resolvedPath);
    for (int i = 0; i < 6; i++) {
      if (await file.exists()) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!await file.exists()) return;
    if (!await _waitForFileStable(file)) return;

    _rememberHandled(resolvedPath);
    await _processPhoto(resolvedPath, isResoniteHint: false);
  }

  void _rememberHandled(String photoPath) {
    if (_handledPhotos.length >= 500) {
      _handledPhotos.remove(_handledPhotos.first);
    }
    _handledPhotos.add(photoPath);
  }

  Future<bool> _waitForFileStable(File file) async {
    int lastSize = -1;
    for (int i = 0; i < 10; i++) {
      try {
        if (!await file.exists()) return false;
        final size = await file.length();
        if (size > 0 && size == lastSize) return true;
        lastSize = size;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return lastSize > 0;
  }

  Future<void> _processPhoto(
    String sourcePath, {
    required bool isResoniteHint,
  }) async {
    final config = _config;
    if (config == null) return;

    try {
      final file = File(sourcePath);
      if (!await file.exists()) return;

      final primaryAuth = await _storage.loadAuthData(secondary: false);
      final secondaryAuth = await _storage.loadAuthData(secondary: true);

      final authParams =
          primaryAuth != null
              ? {
                'userId': primaryAuth.userId,
                'displayName': primaryAuth.displayName,
              }
              : null;

      final parsedMetadata = extractVrcxMetadataSync({
        'imagePath': sourcePath,
        'authParams': authParams,
      });

      final bool isResonite =
          isResoniteHint ||
          parsedMetadata?.application == 'Resonite' ||
          (config.resonitePhotosDirectory.isNotEmpty &&
              path.isWithin(config.resonitePhotosDirectory, sourcePath));

      final LogMetadata? logMetadata =
          isResonite ? null : await _logParser.getLatestLogMetadata(config);

      final uploadAuth = _pickUploadAuth(
        isResonite: isResonite,
        primaryAuth: primaryAuth,
        secondaryAuth: secondaryAuth,
      );

      final badges =
          uploadAuth?.badges.map((b) => b.toLowerCase()).toList() ?? const [];

      final webpPath = await _compressToWebP(
        sourcePath,
        badges,
        isResonite: isResonite,
      );
      if (webpPath == null) return;

      final stats = await file.stat();
      final filename = path.basename(sourcePath);
      final photoMetadata = PhotoMetadata(
        takenDate: stats.modified.millisecondsSinceEpoch,
        filename: filename,
        views: 0,
        world: parsedMetadata?.world ?? logMetadata?.world,
        players: parsedMetadata?.players ?? logMetadata?.players ?? const [],
        localPath: sourcePath,
        application: isResonite ? 'Resonite' : parsedMetadata?.application,
        takenGlobalPosition: parsedMetadata?.takenGlobalPosition,
        takenGlobalRotation: parsedMetadata?.takenGlobalRotation,
        takenGlobalScale: parsedMetadata?.takenGlobalScale,
        cameraFov: parsedMetadata?.cameraFov,
        cameraManufacturer: parsedMetadata?.cameraManufacturer,
        takenById: parsedMetadata?.takenById,
        isNonVrcx:
            isResonite
                ? false
                : (parsedMetadata?.isNonVrcx ??
                    (parsedMetadata?.world == null &&
                        logMetadata?.world == null)),
      );

      await _storage.savePhotoMetadata(photoMetadata, primaryAuth: primaryAuth);

      var metadataDetails = 'Metadata saved locally';
      if (photoMetadata.world != null) {
        metadataDetails +=
            ' (World: ${photoMetadata.world!.name}, Players: ${photoMetadata.players.length})';
      }
      _recordEvent('info', metadataDetails, photoPath: sourcePath);
      _emitEvent('photoAdded', {'path': sourcePath});

      if (config.uploadEnabled) {
        _recordEvent('info', 'Starting upload process...', photoPath: sourcePath);
        await _uploadPhoto(
          webpPath: webpPath,
          originalPath: sourcePath,
          photoMetadata: photoMetadata,
          config: config,
          isResonite: isResonite,
          uploadAuth: uploadAuth,
          primaryAuth: primaryAuth,
          secondaryAuth: secondaryAuth,
        );
      } else {
        _recordEvent(
          'success',
          'Photo processing completed successfully',
          photoPath: sourcePath,
        );
        await _tryDelete(webpPath);
      }
    } catch (e) {
      _recordEvent(
        'processing',
        'Unexpected error processing photo: $e',
        photoPath: sourcePath,
      );
    } finally {
      await _storage.shrinkMemory();
      _platform.trimMemory();
    }
  }

  AuthData? _pickUploadAuth({
    required bool isResonite,
    required AuthData? primaryAuth,
    required AuthData? secondaryAuth,
  }) {
    if (isResonite) {
      if (primaryAuth != null && primaryAuth.userId.startsWith('U-')) {
        return primaryAuth;
      }
      if (secondaryAuth != null && secondaryAuth.userId.startsWith('U-')) {
        return secondaryAuth;
      }
      return null;
    } else {
      if (primaryAuth != null && !primaryAuth.userId.startsWith('U-')) {
        return primaryAuth;
      }
      if (secondaryAuth != null && !secondaryAuth.userId.startsWith('U-')) {
        return secondaryAuth;
      }
      return null;
    }
  }

  Map<String, int> _getTierSettings(List<String> badges) {
    if (badges.contains('mega_supporter') ||
        badges.contains('mega supporter')) {
      return {
        'maxDimension': 7680,
        'webpQuality': 95,
        'maxSizeBytes': 5242880,
      };
    } else if (badges.contains('super_supporter') ||
        badges.contains('super supporter')) {
      return {
        'maxDimension': 3840,
        'webpQuality': 92,
        'maxSizeBytes': 2621440,
      };
    } else if (badges.contains('supporter')) {
      return {
        'maxDimension': 2560,
        'webpQuality': 90,
        'maxSizeBytes': 1048576,
      };
    }
    return {
      'maxDimension': 1920,
      'webpQuality': 85,
      'maxSizeBytes': 153600,
    };
  }

  bool _isValidAspectRatio(int width, int height) {
    const tol = 0.01;
    final ratio = width / height;
    const landscape = 16.0 / 9.0;
    const portrait = 9.0 / 16.0;
    return (ratio - landscape).abs() < tol || (ratio - portrait).abs() < tol;
  }

  Future<String?> _compressToWebP(
    String sourcePath,
    List<String> badges, {
    required bool isResonite,
  }) async {
    final cwebpPath = DaemonPaths.getCwebpPath();
    if (cwebpPath == null) {
      _recordEvent('processing', 'cwebp binary not found', photoPath: sourcePath);
      return null;
    }

    final dims = await ImageDimensionsReader.readFromFile(sourcePath);
    if (dims == null || dims.width <= 0 || dims.height <= 0) {
      _recordEvent(
        'processing',
        'Failed to determine image dimensions: ${path.basename(sourcePath)}',
        photoPath: sourcePath,
      );
      return null;
    }

    if (!isResonite && !_isValidAspectRatio(dims.width, dims.height)) {
      final ratio = (dims.width / dims.height).toStringAsFixed(2);
      _recordEvent(
        'processing',
        'Invalid aspect ratio: $ratio (expected 16:9 or 9:16)',
        photoPath: sourcePath,
      );
      return null;
    }

    final tier = _getTierSettings(badges);
    final maxDim = tier['maxDimension']!;
    final maxSizeBytes = tier['maxSizeBytes']!;
    int quality = tier['webpQuality']!;

    int? targetW;
    int? targetH;
    if (dims.width > maxDim || dims.height > maxDim) {
      if (dims.width >= dims.height) {
        targetW = maxDim;
        targetH = (dims.height * maxDim / dims.width).round();
      } else {
        targetH = maxDim;
        targetW = (dims.width * maxDim / dims.height).round();
      }
    }

    final outDir = DaemonPaths.getTempUploadDir();
    final outPath = path.join(
      outDir,
      '${path.basenameWithoutExtension(sourcePath)}.webp',
    );

    for (int attempt = 0; attempt < 5; attempt++) {
      final args = <String>['-m', '4', '-q', quality.toString()];
      if (targetW != null && targetH != null) {
        args.addAll(['-resize', targetW.toString(), targetH.toString()]);
      }
      args.addAll(['-o', outPath, sourcePath]);

      final res = await Process.run(cwebpPath, args);
      if (res.exitCode != 0) {
        _recordEvent(
          'processing',
          'cwebp failed: ${res.stderr}',
          photoPath: sourcePath,
        );
        return null;
      }

      final size = await File(outPath).length();
      if (size <= maxSizeBytes) return outPath;

      quality = (quality - 10).clamp(50, 100);
    }

    return File(outPath).existsSync() ? outPath : null;
  }

  Future<bool> _checkVerification(
    AuthData authData, {
    required bool isSecondary,
  }) async {
    final cacheKey = '${authData.userId}:${authData.accessKey}';
    final now = DateTime.now();
    final lastVerified = _verifiedCache[cacheKey];
    if (lastVerified != null &&
        now.difference(lastVerified) < const Duration(minutes: 5)) {
      return true;
    }

    try {
      final resp = await http
          .get(
            Uri.parse(
              '$_verifyStatusEndpoint/${Uri.encodeComponent(authData.userId)}',
            ),
            headers: {
              'Authorization': 'Bearer ${authData.accessKey}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 401 ||
          resp.statusCode == 403 ||
          resp.statusCode == 404) {
        _verifiedCache.remove(cacheKey);
        return false;
      }
      if (resp.statusCode != 200) return true;
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final verified =
          decoded['status'] == 'verified' || decoded['verified'] == true;
      if (verified) {
        _verifiedCache[cacheKey] = now;
        await _refreshProfileFromMe(
          authData,
          isSecondary: isSecondary,
          fallbackAgeVerified: decoded['ageVerified'] as bool?,
        );
      } else {
        _verifiedCache.remove(cacheKey);
      }
      return verified;
    } catch (_) {
      return true;
    }
  }

  Future<void> _refreshProfileFromMe(
    AuthData authData, {
    required bool isSecondary,
    bool? fallbackAgeVerified,
  }) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_authMeEndpoint?cache=false'),
            headers: {
              'Authorization': 'Bearer ${authData.accessKey}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      final rawBadges = decoded['badges'];
      final badges =
          rawBadges is List
              ? rawBadges.map((b) => b.toString()).toList()
              : authData.badges;
      final updated = AuthData(
        accessKey: authData.accessKey,
        userId: authData.userId,
        displayName:
            decoded['displayName'] as String? ??
            decoded['name'] as String? ??
            authData.displayName,
        avatarUrl:
            decoded['avatarUrl'] as String? ??
            decoded['pfp'] as String? ??
            authData.avatarUrl,
        badges: badges,
        ageVerified:
            decoded['ageVerified'] as bool? ??
            fallbackAgeVerified ??
            authData.ageVerified,
      );
      if (updated != authData) {
        await _storage.saveAuthData(updated, secondary: isSecondary);
      }
    } catch (_) {}
  }

  Future<bool> _needsToAcceptTOS(AuthData authData) async {
    final cacheKey = '${authData.userId}:${authData.accessKey}';
    final now = DateTime.now();
    final lastAccepted = _tosAcceptedCache[cacheKey];
    if (lastAccepted != null &&
        now.difference(lastAccepted) < const Duration(minutes: 5)) {
      return false;
    }
    try {
      final resp = await http
          .get(
            Uri.parse(_tosStatusEndpoint),
            headers: {'Authorization': 'Bearer ${authData.accessKey}'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body) as Map<String, dynamic>;
        final needs = decoded['needsToAccept'] == true;
        if (!needs) {
          _tosAcceptedCache[cacheKey] = now;
        } else {
          _tosAcceptedCache.remove(cacheKey);
        }
        return needs;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _uploadPhoto({
    required String webpPath,
    required String originalPath,
    required PhotoMetadata photoMetadata,
    required ConfigModel config,
    required bool isResonite,
    required AuthData? uploadAuth,
    required AuthData? primaryAuth,
    required AuthData? secondaryAuth,
  }) async {
    try {
      if (uploadAuth == null) {
        _recordEvent(
          'upload',
          'No authentication data found for ${isResonite ? "Resonite" : "VRChat"}. Please log in.',
          photoPath: originalPath,
        );
        return;
      }

      final isSecondary =
          secondaryAuth != null && secondaryAuth.userId == uploadAuth.userId;
      final isVerified = await _checkVerification(
        uploadAuth,
        isSecondary: isSecondary,
      );
      if (!isVerified) {
        _recordEvent(
          'upload',
          'Account ${uploadAuth.displayName ?? uploadAuth.userId} is not verified. Please verify your account in the Account tab',
          photoPath: originalPath,
        );
        return;
      }

      if (await _needsToAcceptTOS(uploadAuth)) {
        _recordEvent(
          'upload',
          'You need to accept the Terms of Service before uploading photos.',
          photoPath: originalPath,
        );
        return;
      }

      if (isResonite) {
        if (photoMetadata.takenById != null &&
            photoMetadata.takenById != uploadAuth.userId) {
          _recordEvent(
            'upload',
            'Photo taken by ${photoMetadata.takenById}, but logged in as ${uploadAuth.userId}. Skipping upload.',
            photoPath: originalPath,
          );
          return;
        }
        if (photoMetadata.cameraManufacturer == null ||
            photoMetadata.cameraManufacturer!.isEmpty) {
          _recordEvent(
            'upload',
            'Resonite screenshot detected (no CameraManufacturer metadata). Skipping upload.',
            photoPath: originalPath,
          );
          return;
        }
      }

      var metaToUpload = photoMetadata;
      if (metaToUpload.application == 'VRChat') {
        metaToUpload = metaToUpload.copyWith(
          players: [
            Player(
              id: uploadAuth.userId,
              name: uploadAuth.displayName ?? uploadAuth.userId,
            ),
          ],
        );
      }

      await _storage.savePhotoMetadata(metaToUpload, primaryAuth: primaryAuth);

      final metadataBase64 = base64.encode(
        utf8.encode(json.encode(metaToUpload.toJson())),
      );
      final uploadUrlStr =
          'https://api.gallevr.app/vrchat/photo/upload?user=${Uri.encodeComponent(uploadAuth.userId)}&type=webp';

      String? galleryUrl;
      try {
        final curlRes = await Process.run('curl', [
          '-s',
          '-X',
          'POST',
          uploadUrlStr,
          '-H',
          'Content-Type: application/octet-stream',
          '-H',
          'Authorization: Bearer ${uploadAuth.accessKey}',
          '-H',
          'metadata: $metadataBase64',
          '--data-binary',
          '@$webpPath',
        ]);
        if (curlRes.exitCode == 0) {
          final body = curlRes.stdout.toString().trim();
          if (body.startsWith('http://') || body.startsWith('https://')) {
            galleryUrl = body;
          }
        }
      } catch (_) {}

      if (galleryUrl == null) {
        final bytes = await File(webpPath).readAsBytes();
        final req = http.Request('POST', Uri.parse(uploadUrlStr));
        req.bodyBytes = bytes;
        req.headers['Content-Type'] = 'application/octet-stream';
        req.headers['Authorization'] = 'Bearer ${uploadAuth.accessKey}';
        req.headers['metadata'] = metadataBase64;
        final streamed = await req.send().timeout(const Duration(seconds: 30));
        final resp = await http.Response.fromStream(streamed);
        if (resp.statusCode == 200) {
          galleryUrl = resp.body.trim();
        } else {
          _recordEvent(
            'upload',
            'Upload failed with status ${resp.statusCode}: ${resp.body}',
            photoPath: originalPath,
          );
          return;
        }
      }

      final updatedMeta = metaToUpload.copyWith(galleryUrl: galleryUrl);
      await _storage.savePhotoMetadata(updatedMeta, primaryAuth: primaryAuth);

      _recordEvent(
        'success',
        'Photo uploaded successfully',
        photoPath: originalPath,
      );
      _emitEvent('photoUploaded', {'path': originalPath, 'url': galleryUrl});

      if (config.soundEnabled) {
        await _platform.playUploadSound(config.soundVolume);
      }

      if (config.autoCopyGalleryUrl && galleryUrl.isNotEmpty) {
        await _platform.copyToClipboard(galleryUrl);
        _recordEvent(
          'info',
          'Gallery URL copied to clipboard',
          photoPath: originalPath,
        );
      }
    } finally {
      await _tryDelete(webpPath);
    }
  }

  Future<void> _tryDelete(String filePath) async {
    try {
      final f = File(filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
