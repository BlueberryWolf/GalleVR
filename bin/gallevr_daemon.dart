import 'dart:async';
import 'dart:io';

import 'package:gallevr/daemon/daemon_ipc.dart';
import 'package:gallevr/daemon/daemon_paths.dart';
import 'package:gallevr/daemon/daemon_pipeline.dart';
import 'package:gallevr/daemon/daemon_platform.dart';
import 'package:gallevr/daemon/daemon_storage.dart';

Future<void> main(List<String> args) async {
  final platform = DaemonPlatform();

  if (!platform.acquireSingleInstance()) {
    if (!args.contains('--start-minimized')) {
      await platform.wakeOrLaunchUi();
    }
    exit(0);
  }

  final storage = DaemonStorage();
  final token = generateDaemonToken();
  late final DaemonIpcServer ipcServer;
  late final DaemonPipeline pipeline;
  final shutdownCompleter = Completer<void>();

  Future<void> triggerShutdown() async {
    if (shutdownCompleter.isCompleted) return;
    shutdownCompleter.complete();
  }

  pipeline = DaemonPipeline(
    storage: storage,
    platform: platform,
    emitEvent: (event, payload) => ipcServer.broadcastEvent(event, payload),
  );

  ipcServer = DaemonIpcServer(
    token: token,
    onCommand: (cmd, msg) async {
      switch (cmd) {
        case 'ping':
          return {'pid': pid, 'watching': pipeline.isWatching};
        case 'getStatus':
          return {
            'pid': pid,
            'watching': pipeline.isWatching,
            'history': pipeline.history,
          };
        case 'reloadConfig':
          await pipeline.reloadConfig();
          return {'watching': pipeline.isWatching};
        case 'showTrayBalloon':
          final title = msg['title'] as String? ?? 'GalleVR';
          final body = msg['body'] as String? ?? '';
          await platform.showNotification(title, body);
          return {};
        case 'shutdown':
          ipcServer.broadcastEvent('daemonShutdown');
          unawaited(
            Future.delayed(const Duration(milliseconds: 50), triggerShutdown),
          );
          return {};
        default:
          return {};
      }
    },
  );

  final port = await ipcServer.start();
  DaemonInfo.writeToDisk(DaemonInfo(pid: pid, port: port, token: token));

  if (Platform.isWindows) {
    final iconPath = DaemonPaths.getAssetPath('images/app_icon.ico');
    platform.startTray(
      iconPath: iconPath,
      tooltip: 'GalleVR is running in the background',
      onEvent: (eventCode) {
        if (eventCode == kTrayEventOpen) {
          if (ipcServer.hasConnectedClients) {
            ipcServer.broadcastEvent('showUi');
          }
          unawaited(platform.wakeOrLaunchUi());
        } else if (eventCode == kTrayEventHide) {
          ipcServer.broadcastEvent('hideUi');
        } else if (eventCode == kTrayEventExit) {
          ipcServer.broadcastEvent('exitUi');
          unawaited(
            Future.delayed(const Duration(milliseconds: 150), triggerShutdown),
          );
        }
      },
    );
  }

  await pipeline.reloadConfig();

  if (args.contains('--start-minimized')) {
    unawaited(
      Future.delayed(const Duration(seconds: 2), () {
        return platform.showNotification(
          'GalleVR Started',
          'GalleVR is running in the background. Click the tray icon to open.',
        );
      }),
    );
  }

  Timer(const Duration(seconds: 2), () {
    unawaited(storage.shrinkMemory());
    platform.trimMemory();
  });

  try {
    ProcessSignal.sigint.watch().listen((_) => triggerShutdown());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => triggerShutdown());
    }
  } catch (_) {}

  await shutdownCompleter.future;

  platform.stopTray();
  await pipeline.stopWatching();
  await ipcServer.stop();
  await storage.close();
  DaemonInfo.removeFromDisk();
  platform.releaseSingleInstance();
  exit(0);
}
