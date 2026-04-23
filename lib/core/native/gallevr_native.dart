import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

// FFI signatures
typedef ExtractVrcxMetadataNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> filePath);
typedef ExtractVrcxMetadataDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> filePath);

typedef FreeMetadataNative = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef FreeMetadataDart = void Function(ffi.Pointer<Utf8> ptr);

class GalleVrNative {
  static final GalleVrNative _instance = GalleVrNative._internal();
  factory GalleVrNative() => _instance;

  late final ffi.DynamicLibrary _lib;
  late final ExtractVrcxMetadataDart _extractVrcxMetadata;
  late final FreeMetadataDart _freeMetadata;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  GalleVrNative._internal() {
    try {
      _lib = _loadLibrary();
      _extractVrcxMetadata = _lib
          .lookup<ffi.NativeFunction<ExtractVrcxMetadataNative>>('extract_vrcx_metadata')
          .asFunction();
      _freeMetadata = _lib
          .lookup<ffi.NativeFunction<FreeMetadataNative>>('free_metadata')
          .asFunction();
      _isLoaded = true;
    } catch (e) {
      developer.log('Failed to load gallevr_core library: $e', name: 'GalleVrNative');
    }
  }

  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      final possiblePaths = [
        'gallevr_core.dll',
        path.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug', 'gallevr_core.dll'),
        path.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'gallevr_core.dll'),
        path.join(Directory.current.path, 'build', 'windows', 'x64', 'gallevr_core', 'Debug', 'gallevr_core.dll'),
        path.join(Directory.current.path, 'build', 'windows', 'x64', 'gallevr_core', 'Release', 'gallevr_core.dll'),
      ];

      for (final path in possiblePaths) {
        if (File(path).existsSync()) {
          return ffi.DynamicLibrary.open(path);
        }
      }
      
      return ffi.DynamicLibrary.open('gallevr_core.dll');
    } else if (Platform.isLinux) {
      final possiblePaths = [
        'libgallevr_core.so',
        path.join(path.dirname(Platform.resolvedExecutable), 'lib', 'libgallevr_core.so'),
      ];

      for (final p in possiblePaths) {
        if (File(p).existsSync()) {
          return ffi.DynamicLibrary.open(p);
        }
      }

      return ffi.DynamicLibrary.open('libgallevr_core.so');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  String? extractVrcxMetadata(String filePath) {
    if (!_isLoaded) return null;

    final filePathPtr = filePath.toNativeUtf8();
    try {
      final resultPtr = _extractVrcxMetadata(filePathPtr);
      if (resultPtr == ffi.nullptr) return null;

      final result = resultPtr.toDartString();
      _freeMetadata(resultPtr);
      return result;
    } catch (e) {
      return null;
    } finally {
      malloc.free(filePathPtr);
    }
  }
}
