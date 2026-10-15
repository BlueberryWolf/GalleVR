import 'dart:io';

abstract class PlatformService {
  PlatformType getPlatformType();

  Future<String> getPhotosDirectory();

  Future<String> getResonitePhotosDirectory();

  Future<String> getLogsDirectory();

  Future<String> getConfigDirectory();

  Stream<FileSystemEvent> watchDirectory(String path);
}

enum PlatformType { windows, android, linux, unknown }
