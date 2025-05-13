// Configuration model for GalleVR
class ConfigModel {
  // Whether sound is enabled for notifications
  final bool soundEnabled;

  // Volume level for notification sounds (0.0 to 1.0)
  final double soundVolume;

  // Directory where VRChat photos are stored
  final String photosDirectory;

  // Directory where VRChat logs are stored
  final String logsDirectory;

  // Delay in seconds before compressing a photo
  final double compressionDelay;

  // Whether to enable automatic uploading
  final bool uploadEnabled;

  // Whether to minimize to system tray instead of closing
  final bool minimizeToTray;

  // Whether to start the application when Windows starts
  final bool startWithWindows;

  // Whether to automatically copy gallery URL to clipboard after upload
  final bool autoCopyGalleryUrl;

  // Default constructor
  ConfigModel({
    this.soundEnabled = true,
    this.soundVolume = 0.5,
    this.photosDirectory = '',
    this.logsDirectory = '',
    this.compressionDelay = 0.5,
    this.uploadEnabled = true,
    this.minimizeToTray = true,
    this.startWithWindows = false,
    this.autoCopyGalleryUrl = false,
  });

  // Create a ConfigModel from JSON
  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    return ConfigModel(
      soundEnabled: json['soundEnabled'] ?? true,
      soundVolume: (json['soundVolume'] ?? 0.5).toDouble(),
      photosDirectory: json['photosDirectory'] ?? '',
      logsDirectory: json['logsDirectory'] ?? '',
      compressionDelay: (json['compressionDelay'] ?? 0.5).toDouble(),
      uploadEnabled: json['uploadEnabled'] ?? true,
      minimizeToTray: json['minimizeToTray'] ?? true,
      startWithWindows: json['startWithWindows'] ?? false,
      autoCopyGalleryUrl: json['autoCopyGalleryUrl'] ?? false,
    );
  }

  // Convert ConfigModel to JSON
  Map<String, dynamic> toJson() {
    return {
      'soundEnabled': soundEnabled,
      'soundVolume': soundVolume,
      'photosDirectory': photosDirectory,
      'logsDirectory': logsDirectory,
      'compressionDelay': compressionDelay,
      'uploadEnabled': uploadEnabled,
      'minimizeToTray': minimizeToTray,
      'startWithWindows': startWithWindows,
      'autoCopyGalleryUrl': autoCopyGalleryUrl,
    };
  }

  // Create a copy of ConfigModel with some fields replaced
  ConfigModel copyWith({
    bool? soundEnabled,
    double? soundVolume,
    String? photosDirectory,
    String? logsDirectory,
    double? compressionDelay,
    bool? uploadEnabled,
    bool? minimizeToTray,
    bool? startWithWindows,
    bool? autoCopyGalleryUrl,
  }) {
    return ConfigModel(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundVolume: soundVolume ?? this.soundVolume,
      photosDirectory: photosDirectory ?? this.photosDirectory,
      logsDirectory: logsDirectory ?? this.logsDirectory,
      compressionDelay: compressionDelay ?? this.compressionDelay,
      uploadEnabled: uploadEnabled ?? this.uploadEnabled,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      autoCopyGalleryUrl: autoCopyGalleryUrl ?? this.autoCopyGalleryUrl,
    );
  }
}
