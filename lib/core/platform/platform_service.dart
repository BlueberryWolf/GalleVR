import 'dart:io';

// Abstract class defining platform-specific operations
abstract class PlatformService {
  // Get the current platform type
  PlatformType getPlatformType();
  
  // Get the VRChat photos directory
  Future<String> getPhotosDirectory();
  
  // Get the VRChat logs directory
  Future<String> getLogsDirectory();
  
  // Get the app's configuration directory
  Future<String> getConfigDirectory();
  
  // Create a file watcher for the given directory
  // Returns a Stream of file system events
  Stream<FileSystemEvent> watchDirectory(String path);
}

// Enum representing supported platforms
enum PlatformType {
  windows,
  android,
  unknown
}
