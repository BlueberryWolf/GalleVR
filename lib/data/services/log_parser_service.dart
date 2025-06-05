import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:developer' as developer;

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../models/log_metadata.dart';
import '../models/config_model.dart';

// Service for parsing VRChat logs
class LogParserService {
  // Platform service for platform-specific operations
  final PlatformService platformService;

  // Regular expressions for parsing logs
  static final _roomNameRegex = RegExp(r'\[Behaviour\] Entering Room: (.*?)(?:\r?\n|$)');

  static final _worldPatterns = [
    _WorldPattern(
      regex: RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~([^(]+)\(([^)]+)\)~canRequestInvite~region\(([^)]+)\)'),
      handler: (matches, roomName) => WorldInfo(
        name: roomName,
        id: matches[1]!,
        instanceId: matches[2],
        accessType: matches[3],
        ownerId: matches[4],
        region: matches[5],
        canRequestInvite: true,
      ),
    ),
    _WorldPattern(
      regex: RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~([^(]+)\(([^)]+)\)~region\(([^)]+)\)'),
      handler: (matches, roomName) => WorldInfo(
        name: roomName,
        id: matches[1]!,
        instanceId: matches[2],
        accessType: matches[3],
        ownerId: matches[4],
        region: matches[5],
      ),
    ),
    _WorldPattern(
      regex: RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~group\(([^)]+)\)~groupAccessType\(([^)]+)\)~region\(([^)]+)\)'),
      handler: (matches, roomName) => WorldInfo(
        name: roomName,
        id: matches[1]!,
        instanceId: matches[2],
        accessType: 'group',
        groupId: matches[3],
        groupAccessType: matches[4],
        region: matches[5],
      ),
    ),
    _WorldPattern(
      regex: RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~group\(([^)]+)\)~groupAccessType\(([^)]+)\)~inviteOnly~region\(([^)]+)\)'),
      handler: (matches, roomName) => WorldInfo(
        name: roomName,
        id: matches[1]!,
        instanceId: matches[2],
        accessType: 'group',
        groupId: matches[3],
        groupAccessType: matches[4],
        region: matches[5],
        inviteOnly: true,
      ),
    ),
    _WorldPattern(
      regex: RegExp(r'\[Behaviour\] Joining (wrld_[^:]+):([^~]+)~region\(([^)]+)\)'),
      handler: (matches, roomName) => WorldInfo(
        name: roomName,
        id: matches[1]!,
        instanceId: matches[2],
        accessType: 'public',
        region: matches[3],
      ),
    ),
  ];

  static final _playerRegex = RegExp(r'\[Behaviour\] OnPlayer(Joined|Left) (.+?) \((.+?)\)');

  // Default constructor
  LogParserService({PlatformService? platformService})
      : platformService = platformService ?? PlatformServiceFactory.getPlatformService();

  // Get metadata from the latest log file
  Future<LogMetadata?> getLatestLogMetadata(ConfigModel config) async {
    try {
      final logPath = await _findLatestLogFile(config.logsDirectory);
      if (logPath == null) {
        return LogMetadata(players: []);
      }

      final logFile = File(logPath);
      if (!await logFile.exists()) {
        return LogMetadata(players: []);
      }

      final logContent = await logFile.readAsString();

      // Find the last world entry
      final lastEnteringIndex = [
        logContent.lastIndexOf('[Behaviour] Entering world'),
        logContent.lastIndexOf('[Behaviour] Entering Room'),
      ].reduce((a, b) => a > b ? a : b);

      if (lastEnteringIndex == -1) {
        return LogMetadata(players: []);
      }

      final relevantLog = logContent.substring(lastEnteringIndex);

      // Extract room name
      String roomName = '';
      final roomNameMatch = _roomNameRegex.firstMatch(relevantLog);
      if (roomNameMatch != null && roomNameMatch.groupCount >= 1) {
        roomName = roomNameMatch.group(1)?.trim() ?? '';
      }

      // Extract world info
      WorldInfo? worldInfo;
      for (final pattern in _worldPatterns) {
        final match = pattern.regex.firstMatch(relevantLog);
        if (match != null) {
          final groups = List<String?>.generate(
            match.groupCount + 1,
            (i) => i == 0 ? null : match.group(i),
          );
          worldInfo = pattern.handler(groups, roomName);
          break;
        }
      }

      // Furality hotfix
      // If no world info was found but we have a room name, create a basic WorldInfo
      if (worldInfo == null && roomName.isNotEmpty) {
        final worldIdMatch = RegExp(r'Joining (wrld_[^:]+):').firstMatch(relevantLog);
        final worldId = worldIdMatch?.group(1) ?? '';
        
        worldInfo = WorldInfo(
          name: roomName,
          id: worldId,
        );
      }

      // Extract players
      final playerMap = <String, String>{};
      final playerMatches = _playerRegex.allMatches(relevantLog).toList();

      for (final match in playerMatches) {
        if (match.groupCount >= 3) {
          final action = match.group(1);
          final name = match.group(2) ?? '';
          final id = match.group(3) ?? '';

          if (action == 'Joined') {
            playerMap[id] = name;
          } else if (action == 'Left') {
            playerMap.remove(id);
          }
        }
      }

      final players = playerMap.entries
          .map((e) => Player(id: e.key, name: e.value))
          .toList();

      return LogMetadata(
        world: worldInfo,
        players: players,
      );
    } catch (e) {
      developer.log('Error parsing log: $e', name: 'LogParserService');
      return LogMetadata(players: []);
    }
  }

  // Find the latest log file
  Future<String?> _findLatestLogFile(String logsDirectory) async {
    if (logsDirectory.isEmpty) {
      developer.log('Logs directory is empty', name: 'LogParserService');
      return null;
    }

    try {
      final logsDir = Directory(logsDirectory);
      if (!await logsDir.exists()) {
        developer.log('Logs directory does not exist: $logsDirectory', name: 'LogParserService');
        return null;
      }

      developer.log('Searching for log files in: $logsDirectory', name: 'LogParserService');

      // Use the same pattern for both platforms since logs are named the same
      const logPattern = 'output_log_';

      // Find all log files
      final logFiles = <FileSystemEntity>[];
      final allFiles = <String>[];

      await for (final entity in logsDir.list()) {
        final fileName = path.basename(entity.path);
        allFiles.add(fileName);

        if (entity is File && fileName.startsWith(logPattern)) {
          developer.log('Found log file: $fileName', name: 'LogParserService');
          logFiles.add(entity);
        }
      }

      if (logFiles.isEmpty) {
        developer.log(
          'No log files found matching pattern "$logPattern". All files in directory: $allFiles',
          name: 'LogParserService',
        );

        return null;
      }

      // Sort by modification time (newest first)
      logFiles.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return bTime.compareTo(aTime);
      });

      final selectedFile = logFiles.first.path;
      developer.log('Selected latest log file: ${path.basename(selectedFile)}', name: 'LogParserService');
      return selectedFile;
    } catch (e) {
      developer.log('Error finding latest log file: $e', name: 'LogParserService');
      return null;
    }
  }
}

// Helper class for world pattern matching
class _WorldPattern {
  final RegExp regex;
  final WorldInfo Function(List<String?>, String) handler;

  _WorldPattern({
    required this.regex,
    required this.handler,
  });
}
