class ConfigModel {
  final bool soundEnabled;

  /// Volume level for notification sounds (0.0 to 1.0).
  final double soundVolume;

  final String photosDirectory;

  final String logsDirectory;

  final String resonitePhotosDirectory;

  /// Seconds to wait before compressing a new photo.
  final double compressionDelay;

  final bool uploadEnabled;

  final bool minimizeToTray;

  final bool startWithWindows;

  final bool autoCopyGalleryUrl;

  /// Windows only.
  final bool autoUpdateEnabled;

  ConfigModel({
    this.soundEnabled = true,
    this.soundVolume = 0.5,
    this.photosDirectory = '',
    this.logsDirectory = '',
    this.resonitePhotosDirectory = '',
    this.compressionDelay = 0.5,
    this.uploadEnabled = true,
    this.minimizeToTray = true,
    this.startWithWindows = false,
    this.autoCopyGalleryUrl = false,
    this.autoUpdateEnabled = false,
  });

  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    return ConfigModel(
      soundEnabled: json['soundEnabled'] ?? true,
      soundVolume: (json['soundVolume'] ?? 0.5).toDouble(),
      photosDirectory: json['photosDirectory'] ?? '',
      logsDirectory: json['logsDirectory'] ?? '',
      resonitePhotosDirectory: json['resonitePhotosDirectory'] ?? '',
      compressionDelay: (json['compressionDelay'] ?? 0.5).toDouble(),
      uploadEnabled: json['uploadEnabled'] ?? true,
      minimizeToTray: json['minimizeToTray'] ?? true,
      startWithWindows: json['startWithWindows'] ?? false,
      autoCopyGalleryUrl: json['autoCopyGalleryUrl'] ?? false,
      autoUpdateEnabled: json['autoUpdateEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'soundEnabled': soundEnabled,
      'soundVolume': soundVolume,
      'photosDirectory': photosDirectory,
      'logsDirectory': logsDirectory,
      'resonitePhotosDirectory': resonitePhotosDirectory,
      'compressionDelay': compressionDelay,
      'uploadEnabled': uploadEnabled,
      'minimizeToTray': minimizeToTray,
      'startWithWindows': startWithWindows,
      'autoCopyGalleryUrl': autoCopyGalleryUrl,
      'autoUpdateEnabled': autoUpdateEnabled,
    };
  }

  ConfigModel copyWith({
    bool? soundEnabled,
    double? soundVolume,
    String? photosDirectory,
    String? logsDirectory,
    String? resonitePhotosDirectory,
    double? compressionDelay,
    bool? uploadEnabled,
    bool? minimizeToTray,
    bool? startWithWindows,
    bool? autoCopyGalleryUrl,
    bool? autoUpdateEnabled,
  }) {
    return ConfigModel(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundVolume: soundVolume ?? this.soundVolume,
      photosDirectory: photosDirectory ?? this.photosDirectory,
      logsDirectory: logsDirectory ?? this.logsDirectory,
      resonitePhotosDirectory:
          resonitePhotosDirectory ?? this.resonitePhotosDirectory,
      compressionDelay: compressionDelay ?? this.compressionDelay,
      uploadEnabled: uploadEnabled ?? this.uploadEnabled,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      autoCopyGalleryUrl: autoCopyGalleryUrl ?? this.autoCopyGalleryUrl,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
    );
  }
}
