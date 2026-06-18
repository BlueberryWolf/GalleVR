import 'package:gallevr/data/models/log_metadata.dart';

// Container for VRChat/VRCX metadata
class VrcMetadata {
  final WorldInfo? world;
  final List<Player> players;

  VrcMetadata({
    this.world,
    this.players = const [],
  });

  factory VrcMetadata.fromJson(Map<String, dynamic> json) {
    return VrcMetadata(
      world: json['world'] != null ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>) : null,
      players: (json['players'] as List<dynamic>?)
              ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (world != null) 'world': world!.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
    };
  }

  VrcMetadata merge(VrcMetadata? other) {
    if (other == null) return this;
    return VrcMetadata(
      world: world ?? other.world,
      players: players.isNotEmpty ? players : other.players,
    );
  }
}

// Container for Resonite metadata
class ResoniteMetadata {
  final String? takenGlobalPosition;
  final String? takenGlobalRotation;
  final String? takenGlobalScale;
  final String? cameraFov;
  final String? cameraManufacturer;
  final String? takenById;
  final WorldInfo? world; // locationName / locationUrl
  final List<Player> players;

  ResoniteMetadata({
    this.takenGlobalPosition,
    this.takenGlobalRotation,
    this.takenGlobalScale,
    this.cameraFov,
    this.cameraManufacturer,
    this.takenById,
    this.world,
    this.players = const [],
  });

  factory ResoniteMetadata.fromJson(Map<String, dynamic> json) {
    return ResoniteMetadata(
      takenGlobalPosition: json['takenGlobalPosition'] as String?,
      takenGlobalRotation: json['takenGlobalRotation'] as String?,
      takenGlobalScale: json['takenGlobalScale'] as String?,
      cameraFov: json['cameraFov'] as String?,
      cameraManufacturer: json['cameraManufacturer'] as String?,
      takenById: json['takenById'] as String?,
      world: json['world'] != null ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>) : null,
      players: (json['players'] as List<dynamic>?)
              ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (takenGlobalPosition != null) 'takenGlobalPosition': takenGlobalPosition,
      if (takenGlobalRotation != null) 'takenGlobalRotation': takenGlobalRotation,
      if (takenGlobalScale != null) 'takenGlobalScale': takenGlobalScale,
      if (cameraFov != null) 'cameraFov': cameraFov,
      if (cameraManufacturer != null) 'cameraManufacturer': cameraManufacturer,
      if (takenById != null) 'takenById': takenById,
      if (world != null) 'world': world!.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
    };
  }

  ResoniteMetadata merge(ResoniteMetadata? other) {
    if (other == null) return this;
    return ResoniteMetadata(
      takenGlobalPosition: takenGlobalPosition ?? other.takenGlobalPosition,
      takenGlobalRotation: takenGlobalRotation ?? other.takenGlobalRotation,
      takenGlobalScale: takenGlobalScale ?? other.takenGlobalScale,
      cameraFov: cameraFov ?? other.cameraFov,
      cameraManufacturer: cameraManufacturer ?? other.cameraManufacturer,
      takenById: takenById ?? other.takenById,
      world: world ?? other.world,
      players: players.isNotEmpty ? players : other.players,
    );
  }
}

// Model for photo metadata
class PhotoMetadata {
  // Timestamp when the photo was taken (milliseconds since epoch)
  final int takenDate;

  // Original filename
  final String filename;

  // Number of views
  final int views;

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

  // Containers
  final VrcMetadata? vrcMetadata;
  final ResoniteMetadata? resoniteMetadata;

  // Backwards-compatible getters
  WorldInfo? get world => vrcMetadata?.world ?? resoniteMetadata?.world;
  List<Player> get players => vrcMetadata?.players ?? resoniteMetadata?.players ?? const [];
  String? get takenGlobalPosition => resoniteMetadata?.takenGlobalPosition;
  String? get takenGlobalRotation => resoniteMetadata?.takenGlobalRotation;
  String? get takenGlobalScale => resoniteMetadata?.takenGlobalScale;
  String? get cameraFov => resoniteMetadata?.cameraFov;
  String? get cameraManufacturer => resoniteMetadata?.cameraManufacturer;
  String? get takenById => resoniteMetadata?.takenById;

  // Default constructor
  PhotoMetadata({
    required this.takenDate,
    required this.filename,
    this.views = 0,
    WorldInfo? world,
    List<Player> players = const [],
    this.localPath,
    this.galleryUrl,
    this.remoteId,
    this.isNonVrcx = false,
    this.isEdited = false,
    this.logChecked = false,
    this.application,
    String? takenGlobalPosition,
    String? takenGlobalRotation,
    String? takenGlobalScale,
    String? cameraFov,
    String? cameraManufacturer,
    String? takenById,
    VrcMetadata? vrcMetadata,
    ResoniteMetadata? resoniteMetadata,
  }) : vrcMetadata = vrcMetadata ??
            (application == 'Resonite'
                ? null
                : VrcMetadata(world: world, players: players)),
       resoniteMetadata = resoniteMetadata ??
            ((application == 'Resonite' || takenGlobalPosition != null || cameraManufacturer != null)
                ? ResoniteMetadata(
                    takenGlobalPosition: takenGlobalPosition,
                    takenGlobalRotation: takenGlobalRotation,
                    takenGlobalScale: takenGlobalScale,
                    cameraFov: cameraFov,
                    cameraManufacturer: cameraManufacturer,
                    takenById: takenById,
                    world: world,
                    players: players,
                  )
                : null);

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

    final app = json['application'] as String?;
    final vrcJson = json['vrcMetadata'] as Map<String, dynamic>?;
    final resJson = json['resoniteMetadata'] as Map<String, dynamic>?;

    return PhotoMetadata(
      takenDate: takenDateMs,
      filename: json['filename'] as String,
      views: json['views'] as int? ?? 0,
      localPath: json['localPath'] as String?,
      galleryUrl: json['galleryUrl'] as String?,
      remoteId: json['remoteId'] as String?,
      isNonVrcx: json['isNonVrcx'] as bool? ?? false,
      isEdited: json['isEdited'] as bool? ?? false,
      logChecked: json['logChecked'] as bool? ?? false,
      application: app,
      vrcMetadata: vrcJson != null
          ? VrcMetadata.fromJson(vrcJson)
          : (app == 'Resonite'
              ? null
              : VrcMetadata(
                  world: json['world'] != null ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>) : null,
                  players: (json['players'] as List<dynamic>?)
                          ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
                          .toList() ??
                      [],
                )),
      resoniteMetadata: resJson != null
          ? ResoniteMetadata.fromJson(resJson)
          : ((app == 'Resonite' || json['takenGlobalPosition'] != null)
              ? ResoniteMetadata(
                  takenGlobalPosition: json['takenGlobalPosition'] as String?,
                  takenGlobalRotation: json['takenGlobalRotation'] as String?,
                  takenGlobalScale: json['takenGlobalScale'] as String?,
                  cameraFov: json['cameraFov'] as String?,
                  cameraManufacturer: json['cameraManufacturer'] as String?,
                  takenById: json['takenById'] as String?,
                  world: json['world'] != null ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>) : null,
                  players: (json['players'] as List<dynamic>?)
                          ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
                          .toList() ??
                      [],
                )
              : null),
    );
  }

  // Convert PhotoMetadata to JSON
  Map<String, dynamic> toJson() {
    return {
      'takenDate': takenDate,
      'filename': filename,
      'views': views,
      if (localPath != null) 'localPath': localPath,
      if (galleryUrl != null) 'galleryUrl': galleryUrl,
      if (remoteId != null) 'remoteId': remoteId,
      'isNonVrcx': isNonVrcx,
      'isEdited': isEdited,
      'logChecked': logChecked,
      if (application != null) 'application': application,
      if (vrcMetadata != null) 'vrcMetadata': vrcMetadata!.toJson(),
      if (resoniteMetadata != null) 'resoniteMetadata': resoniteMetadata!.toJson(),
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
    VrcMetadata? vrcMetadata,
    ResoniteMetadata? resoniteMetadata,
  }) {
    return PhotoMetadata(
      takenDate: takenDate ?? this.takenDate,
      filename: filename ?? this.filename,
      views: views ?? this.views,
      localPath: localPath ?? this.localPath,
      galleryUrl: galleryUrl ?? this.galleryUrl,
      remoteId: remoteId ?? this.remoteId,
      isNonVrcx: isNonVrcx ?? this.isNonVrcx,
      isEdited: isEdited ?? this.isEdited,
      logChecked: logChecked ?? this.logChecked,
      application: application ?? this.application,
      vrcMetadata: vrcMetadata ??
          (world != null || players != null
              ? VrcMetadata(
                  world: world ?? this.world,
                  players: players ?? this.players,
                )
              : this.vrcMetadata),
      resoniteMetadata: resoniteMetadata ??
          (takenGlobalPosition != null ||
                  takenGlobalRotation != null ||
                  takenGlobalScale != null ||
                  cameraFov != null ||
                  cameraManufacturer != null ||
                  takenById != null ||
                  world != null ||
                  players != null
              ? ResoniteMetadata(
                  takenGlobalPosition: takenGlobalPosition ?? this.takenGlobalPosition,
                  takenGlobalRotation: takenGlobalRotation ?? this.takenGlobalRotation,
                  takenGlobalScale: takenGlobalScale ?? this.takenGlobalScale,
                  cameraFov: cameraFov ?? this.cameraFov,
                  cameraManufacturer: cameraManufacturer ?? this.cameraManufacturer,
                  takenById: takenById ?? this.takenById,
                  world: world ?? this.world,
                  players: players ?? this.players,
                )
              : this.resoniteMetadata),
    );
  }

  // Unified merge method
  PhotoMetadata merge(PhotoMetadata other, {required bool isRemote}) {
    if (isRemote) {
      return copyWith(
        localPath: other.localPath ?? localPath,
        isNonVrcx: false,
        isEdited: other.isEdited || isEdited,
        takenDate: other.takenDate, // Prefer local file stats/metadata
        logChecked: other.logChecked || logChecked,
        application: other.application ?? application,
        vrcMetadata: vrcMetadata != null
            ? vrcMetadata!.merge(other.vrcMetadata)
            : other.vrcMetadata,
        resoniteMetadata: resoniteMetadata != null
            ? resoniteMetadata!.merge(other.resoniteMetadata)
            : other.resoniteMetadata,
      );
    } else {
      return copyWith(
        galleryUrl: (galleryUrl != null && galleryUrl!.isNotEmpty)
            ? galleryUrl
            : other.galleryUrl,
        views: other.views > views ? other.views : views,
        isEdited: other.isEdited || isEdited,
        isNonVrcx: (other.galleryUrl != null ||
                other.world != null ||
                other.players.isNotEmpty ||
                galleryUrl != null ||
                world != null ||
                players.isNotEmpty)
            ? false
            : isNonVrcx,
        logChecked: other.logChecked || logChecked,
        application: application ?? other.application,
        vrcMetadata: vrcMetadata != null
            ? vrcMetadata!.merge(other.vrcMetadata)
            : other.vrcMetadata,
        resoniteMetadata: resoniteMetadata != null
            ? resoniteMetadata!.merge(other.resoniteMetadata)
            : other.resoniteMetadata,
      );
    }
  }
}
