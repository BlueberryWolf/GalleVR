import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import 'daemon_paths.dart';

const int kTrayEventOpen = 1;
const int kTrayEventHide = 2;
const int kTrayEventExit = 3;

typedef _AcquireMutexNative = ffi.Int32 Function();
typedef _AcquireMutexDart = int Function();

typedef _ReleaseMutexNative = ffi.Void Function();
typedef _ReleaseMutexDart = void Function();

typedef _TrayCallbackNative = ffi.Void Function(ffi.Int32 eventCode);
typedef _TrayStartNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf8> iconPath,
      ffi.Pointer<Utf8> tooltip,
      ffi.Pointer<ffi.NativeFunction<_TrayCallbackNative>> callback,
    );
typedef _TrayStartDart =
    int Function(
      ffi.Pointer<Utf8> iconPath,
      ffi.Pointer<Utf8> tooltip,
      ffi.Pointer<ffi.NativeFunction<_TrayCallbackNative>> callback,
    );

typedef _TraySetTooltipNative = ffi.Void Function(ffi.Pointer<Utf8> tooltip);
typedef _TraySetTooltipDart = void Function(ffi.Pointer<Utf8> tooltip);

typedef _TrayShowBalloonNative =
    ffi.Void Function(ffi.Pointer<Utf8> title, ffi.Pointer<Utf8> body);
typedef _TrayShowBalloonDart =
    void Function(ffi.Pointer<Utf8> title, ffi.Pointer<Utf8> body);

typedef _TrayStopNative = ffi.Void Function();
typedef _TrayStopDart = void Function();

typedef _SetClipboardNative = ffi.Int32 Function(ffi.Pointer<Utf8> text);
typedef _SetClipboardDart = int Function(ffi.Pointer<Utf8> text);

typedef _PlayWavNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8> data, ffi.Int32 length);
typedef _PlayWavDart = int Function(ffi.Pointer<ffi.Uint8> data, int length);

typedef _TrimWorkingSetNative = ffi.Void Function();
typedef _TrimWorkingSetDart = void Function();

typedef _WakeUiWindowNative = ffi.Int32 Function();
typedef _WakeUiWindowDart = int Function();

typedef _LaunchDetachedNative =
    ffi.Int32 Function(ffi.Pointer<Utf8> exePath, ffi.Pointer<Utf8> args);
typedef _LaunchDetachedDart =
    int Function(ffi.Pointer<Utf8> exePath, ffi.Pointer<Utf8> args);

typedef _MallocTrimNative = ffi.Int32 Function(ffi.Size pad);
typedef _MallocTrimDart = int Function(int pad);

class DaemonPlatform {
  ffi.DynamicLibrary? _winLib;
  ffi.NativeCallable<_TrayCallbackNative>? _trayCallable;
  RandomAccessFile? _linuxLockFile;
  _MallocTrimDart? _linuxMallocTrim;

  _AcquireMutexDart? _acquireMutex;
  _ReleaseMutexDart? _releaseMutex;
  _TrayStartDart? _trayStart;
  _TraySetTooltipDart? _traySetTooltip;
  _TrayShowBalloonDart? _trayShowBalloon;
  _TrayStopDart? _trayStop;
  _SetClipboardDart? _setClipboard;
  _PlayWavDart? _playWav;
  _TrimWorkingSetDart? _trimWorkingSet;
  _WakeUiWindowDart? _wakeUiWindow;
  _LaunchDetachedDart? _launchDetached;

  DaemonPlatform() {
    if (Platform.isWindows) {
      _loadWindowsLibrary();
    } else if (Platform.isLinux) {
      try {
        final libc = ffi.DynamicLibrary.open('libc.so.6');
        _linuxMallocTrim =
            libc
                .lookup<ffi.NativeFunction<_MallocTrimNative>>('malloc_trim')
                .asFunction();
      } catch (_) {}
    }
  }

  void _loadWindowsLibrary() {
    final exeDir = DaemonPaths.exeDir;
    final candidates = [
      path.join(exeDir, 'gallevr_core.dll'),
      'gallevr_core.dll',
    ];
    for (final c in candidates) {
      if (File(c).existsSync() || c == 'gallevr_core.dll') {
        try {
          _winLib = ffi.DynamicLibrary.open(c);
          break;
        } catch (_) {}
      }
    }
    final lib = _winLib;
    if (lib == null) return;

    _acquireMutex =
        lib
            .lookup<ffi.NativeFunction<_AcquireMutexNative>>(
              'gallevr_acquire_daemon_mutex',
            )
            .asFunction();
    _releaseMutex =
        lib
            .lookup<ffi.NativeFunction<_ReleaseMutexNative>>(
              'gallevr_release_daemon_mutex',
            )
            .asFunction();
    _trayStart =
        lib
            .lookup<ffi.NativeFunction<_TrayStartNative>>('gallevr_tray_start')
            .asFunction();
    _traySetTooltip =
        lib
            .lookup<ffi.NativeFunction<_TraySetTooltipNative>>(
              'gallevr_tray_set_tooltip',
            )
            .asFunction();
    _trayShowBalloon =
        lib
            .lookup<ffi.NativeFunction<_TrayShowBalloonNative>>(
              'gallevr_tray_show_balloon',
            )
            .asFunction();
    _trayStop =
        lib
            .lookup<ffi.NativeFunction<_TrayStopNative>>('gallevr_tray_stop')
            .asFunction();
    _setClipboard =
        lib
            .lookup<ffi.NativeFunction<_SetClipboardNative>>(
              'gallevr_set_clipboard_utf8',
            )
            .asFunction();
    _playWav =
        lib
            .lookup<ffi.NativeFunction<_PlayWavNative>>(
              'gallevr_play_wav_memory',
            )
            .asFunction();
    _trimWorkingSet =
        lib
            .lookup<ffi.NativeFunction<_TrimWorkingSetNative>>(
              'gallevr_trim_working_set',
            )
            .asFunction();
    _wakeUiWindow =
        lib
            .lookup<ffi.NativeFunction<_WakeUiWindowNative>>(
              'gallevr_wake_ui_window',
            )
            .asFunction();
    _launchDetached =
        lib
            .lookup<ffi.NativeFunction<_LaunchDetachedNative>>(
              'gallevr_launch_detached',
            )
            .asFunction();
  }

  bool acquireSingleInstance() {
    if (Platform.isWindows) {
      if (_acquireMutex == null) return true;
      return _acquireMutex!() == 1;
    } else if (Platform.isLinux) {
      try {
        final lockFile = File(DaemonPaths.getDaemonLockPath());
        _linuxLockFile = lockFile.openSync(mode: FileMode.write);
        _linuxLockFile!.lockSync(FileLock.exclusive);
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  void releaseSingleInstance() {
    if (Platform.isWindows) {
      _releaseMutex?.call();
    } else if (Platform.isLinux) {
      try {
        _linuxLockFile?.unlockSync();
        _linuxLockFile?.closeSync();
      } catch (_) {}
      _linuxLockFile = null;
    }
  }

  bool startTray({
    required String iconPath,
    required String tooltip,
    required void Function(int eventCode) onEvent,
  }) {
    if (!Platform.isWindows || _trayStart == null) return false;

    _trayCallable?.close();
    _trayCallable = ffi.NativeCallable<_TrayCallbackNative>.listener(onEvent);

    final iconPtr = iconPath.toNativeUtf8();
    final tipPtr = tooltip.toNativeUtf8();
    try {
      return _trayStart!(iconPtr, tipPtr, _trayCallable!.nativeFunction) == 1;
    } finally {
      calloc.free(iconPtr);
      calloc.free(tipPtr);
    }
  }

  void setTrayTooltip(String tooltip) {
    if (!Platform.isWindows || _traySetTooltip == null) return;
    final tipPtr = tooltip.toNativeUtf8();
    try {
      _traySetTooltip!(tipPtr);
    } finally {
      calloc.free(tipPtr);
    }
  }

  Future<void> showNotification(String title, String body) async {
    if (Platform.isWindows && _trayShowBalloon != null) {
      final titlePtr = title.toNativeUtf8();
      final bodyPtr = body.toNativeUtf8();
      try {
        _trayShowBalloon!(titlePtr, bodyPtr);
      } finally {
        calloc.free(titlePtr);
        calloc.free(bodyPtr);
      }
    } else if (Platform.isLinux) {
      try {
        await Process.run('notify-send', [title, body]);
      } catch (_) {}
    }
  }

  void stopTray() {
    if (Platform.isWindows) {
      _trayStop?.call();
    }
    _trayCallable?.close();
    _trayCallable = null;
  }

  Future<void> wakeOrLaunchUi() async {
    if (Platform.isWindows) {
      if (_wakeUiWindow != null && _wakeUiWindow!() == 1) {
        return;
      }
      final uiExe = DaemonPaths.getUiExePath();
      if (!File(uiExe).existsSync()) return;
      if (_launchDetached != null) {
        final exePtr = uiExe.toNativeUtf8();
        final argsPtr = ''.toNativeUtf8();
        try {
          _launchDetached!(exePtr, argsPtr);
        } finally {
          calloc.free(exePtr);
          calloc.free(argsPtr);
        }
      } else {
        await Process.start(uiExe, const [], mode: ProcessStartMode.detached);
      }
    } else if (Platform.isLinux) {
      final uiExe = DaemonPaths.getUiExePath();
      if (!File(uiExe).existsSync()) return;
      await Process.start(uiExe, const [], mode: ProcessStartMode.detached);
    }
  }

  Future<void> copyToClipboard(String text) async {
    if (text.isEmpty) return;
    if (Platform.isWindows && _setClipboard != null) {
      final ptr = text.toNativeUtf8();
      try {
        _setClipboard!(ptr);
      } finally {
        calloc.free(ptr);
      }
    } else if (Platform.isLinux) {
      for (final cmd in [
        ['wl-copy'],
        ['xclip', '-selection', 'clipboard'],
        ['xsel', '--clipboard', '--input'],
      ]) {
        try {
          final proc = await Process.start(cmd.first, cmd.sublist(1));
          proc.stdin.write(text);
          await proc.stdin.close();
          final code = await proc.exitCode;
          if (code == 0) return;
        } catch (_) {}
      }
    }
  }

  Future<void> playUploadSound(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (clamped <= 0.0) return;

    final wavPath = DaemonPaths.getAssetPath('sounds/upload_complete.wav');
    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) return;

    if (Platform.isWindows && _playWav != null) {
      try {
        final raw = await wavFile.readAsBytes();
        final scaled = _scaleWavVolume(raw, clamped);
        final ptr = calloc<ffi.Uint8>(scaled.length);
        try {
          ptr.asTypedList(scaled.length).setAll(0, scaled);
          _playWav!(ptr, scaled.length);
        } finally {
          calloc.free(ptr);
        }
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        final paVol = (clamped * 65536).round();
        final res = await Process.run('paplay', [
          '--volume=$paVol',
          wavPath,
        ]);
        if (res.exitCode == 0) return;
      } catch (_) {}
      try {
        await Process.run('aplay', ['-q', wavPath]);
      } catch (_) {}
    }
  }

  Uint8List _scaleWavVolume(Uint8List wav, double volume) {
    if (volume >= 0.99 || wav.length < 44) return wav;
    final copy = Uint8List.fromList(wav);
    final bd = ByteData.sublistView(copy);
    if (copy[0] != 0x52 || copy[1] != 0x49 || copy[2] != 0x46 || copy[3] != 0x46) {
      return copy;
    }
    int offset = 12;
    int bitsPerSample = 0;
    int audioFormat = 0;
    while (offset + 8 <= copy.length) {
      final chunkId = String.fromCharCodes(copy.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;
      if (chunkId == 'fmt ' && dataStart + 16 <= copy.length) {
        audioFormat = bd.getUint16(dataStart, Endian.little);
        bitsPerSample = bd.getUint16(dataStart + 14, Endian.little);
      } else if (chunkId == 'data' && audioFormat == 1 && bitsPerSample == 16) {
        final end = (dataStart + chunkSize).clamp(0, copy.length);
        for (int i = dataStart; i + 1 < end; i += 2) {
          final sample = bd.getInt16(i, Endian.little);
          final scaled = (sample * volume).round().clamp(-32768, 32767);
          bd.setInt16(i, scaled, Endian.little);
        }
        break;
      }
      offset = dataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return copy;
  }

  void trimMemory() {
    if (Platform.isWindows) {
      _trimWorkingSet?.call();
    } else if (Platform.isLinux) {
      _linuxMallocTrim?.call(0);
    }
  }
}
