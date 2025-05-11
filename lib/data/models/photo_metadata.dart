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

  // Default constructor
  PhotoMetadata({
    required this.takenDate,
    required this.filename,
    this.views = 0,
    this.world,
    this.players = const [],
    this.localPath,
    this.galleryUrl,
  });

  // Create a PhotoMetadata from JSON
  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      takenDate: json['takenDate'] as int,
      filename: json['filename'] as String,
      views: json['views'] as int? ?? 0,
      world: json['world'] != null
          ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>)
          : null,
      players: (json['players'] as List<dynamic>?)
          ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      localPath: json['localPath'] as String?,
      galleryUrl: json['galleryUrl'] as String?,
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
  }) {
    return PhotoMetadata(
      takenDate: takenDate ?? this.takenDate,
      filename: filename ?? this.filename,
      views: views ?? this.views,
      world: world ?? this.world,
      players: players ?? this.players,
      localPath: localPath ?? this.localPath,
      galleryUrl: galleryUrl ?? this.galleryUrl,
    );
  }
}
