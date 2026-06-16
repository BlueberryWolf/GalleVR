import 'package:gallevr/data/models/log_metadata.dart';

// Model for photo metadata
class PhotoMetadata {
  // Timestamp when the photo was taken (milliseconds since epoch)
  final int takenDate;

  // Original filename
  final String filename;

  // Number of views
  final int views;

  // World information
  final WorldInfo? world;

  // List of players in the photo
  final List<Player> players;

  // Path to the local file
  final String? localPath;

  // URL to the photo in the gallery
  final String? galleryUrl;

  final String? remoteId;

  // Whether this photo has been scanned and confirmed to have no VRCX metadata
  final bool isNonVrcx;

  // Whether this photo is an edited version
  final bool isEdited;

  // Whether this photo has been checked against logs for metadata recovery
  final bool logChecked;

  // Application that created the metadata (e.g. 'VRCX', 'VRChat', 'Resonite')
  final String? application;

  // Resonite spatial tracking details
  final String? takenGlobalPosition;
  final String? takenGlobalRotation;
  final String? takenGlobalScale;
  final String? cameraFov;
  final String? cameraManufacturer;
  final String? takenById;

  // Default constructor
  PhotoMetadata({
    required this.takenDate,
    required this.filename,
    this.views = 0,
    this.world,
    this.players = const [],
    this.localPath,
    this.galleryUrl,
    this.remoteId,
    this.isNonVrcx = false,
    this.isEdited = false,
    this.logChecked = false,
    this.application,
    this.takenGlobalPosition,
    this.takenGlobalRotation,
    this.takenGlobalScale,
    this.cameraFov,
    this.cameraManufacturer,
    this.takenById,
  });

  // Create a PhotoMetadata from JSON
  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    final rawTakenDate = json['takenDate'];
    int takenDateMs = DateTime.now().millisecondsSinceEpoch;

    if (rawTakenDate is int) {
      takenDateMs = rawTakenDate;
    } else if (rawTakenDate is String) {
      final parsed = DateTime.tryParse(rawTakenDate);
      if (parsed != null) {
        takenDateMs = parsed.millisecondsSinceEpoch;
      }
    }

    return PhotoMetadata(
      takenDate: takenDateMs,
      filename: json['filename'] as String,
      views: json['views'] as int? ?? 0,
      world:
          json['world'] != null
              ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>)
              : null,
      players:
          (json['players'] as List<dynamic>?)
              ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      localPath: json['localPath'] as String?,
      galleryUrl: json['galleryUrl'] as String?,
      remoteId: json['remoteId'] as String?,
      isNonVrcx: json['isNonVrcx'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      logChecked: json['logChecked'] as bool? ?? false,
      application: json['application'] as String?,
      takenGlobalPosition: json['takenGlobalPosition'] as String?,
      takenGlobalRotation: json['takenGlobalRotation'] as String?,
      takenGlobalScale: json['takenGlobalScale'] as String?,
      cameraFov: json['cameraFov'] as String?,
      cameraManufacturer: json['cameraManufacturer'] as String?,
      takenById: json['takenById'] as String?,
    );
  }

  // Convert PhotoMetadata to JSON
  Map<String, dynamic> toJson() {
    return {
      'takenDate': takenDate,
      'filename': filename,
      'views': views,
      'world': world?.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
      if (localPath != null) 'localPath': localPath,
      if (galleryUrl != null) 'galleryUrl': galleryUrl,
      if (remoteId != null) 'remoteId': remoteId,
      'isNonVrcx': isNonVrcx,
      'isEdited': isEdited,
      'logChecked': logChecked,
      if (application != null) 'application': application,
      if (takenGlobalPosition != null) 'takenGlobalPosition': takenGlobalPosition,
      if (takenGlobalRotation != null) 'takenGlobalRotation': takenGlobalRotation,
      if (takenGlobalScale != null) 'takenGlobalScale': takenGlobalScale,
      if (cameraFov != null) 'cameraFov': cameraFov,
      if (cameraManufacturer != null) 'cameraManufacturer': cameraManufacturer,
      if (takenById != null) 'takenById': takenById,
    };
  }

  // Create a copy of this PhotoMetadata with the given fields replaced
  PhotoMetadata copyWith({
    int? takenDate,
    String? filename,
    int? views,
    WorldInfo? world,
    List<Player>? players,
    String? localPath,
    String? galleryUrl,
    String? remoteId,
    bool? isNonVrcx,
    bool? isEdited,
    bool? logChecked,
    String? application,
    String? takenGlobalPosition,
    String? takenGlobalRotation,
    String? takenGlobalScale,
    String? cameraFov,
    String? cameraManufacturer,
    String? takenById,
  }) {
    return PhotoMetadata(
      takenDate: takenDate ?? this.takenDate,
      filename: filename ?? this.filename,
      views: views ?? this.views,
      world: world ?? this.world,
      players: players ?? this.players,
      localPath: localPath ?? this.localPath,
      galleryUrl: galleryUrl ?? this.galleryUrl,
      remoteId: remoteId ?? this.remoteId,
      isNonVrcx: isNonVrcx ?? this.isNonVrcx,
      isEdited: isEdited ?? this.isEdited,
      logChecked: logChecked ?? this.logChecked,
      application: application ?? this.application,
      takenGlobalPosition: takenGlobalPosition ?? this.takenGlobalPosition,
      takenGlobalRotation: takenGlobalRotation ?? this.takenGlobalRotation,
      takenGlobalScale: takenGlobalScale ?? this.takenGlobalScale,
      cameraFov: cameraFov ?? this.cameraFov,
      cameraManufacturer: cameraManufacturer ?? this.cameraManufacturer,
      takenById: takenById ?? this.takenById,
    );
  }
}
