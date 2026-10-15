class WorldInfo {
  final String name;

  final String id;

  final String? instanceId;

  /// Access type (public, friends+, etc.).
  final String? accessType;

  final String? region;

  final String? ownerId;

  final String? groupId;

  final String? groupAccessType;

  final bool? canRequestInvite;

  final bool? inviteOnly;

  WorldInfo({
    required this.name,
    required this.id,
    this.instanceId,
    this.accessType,
    this.region,
    this.ownerId,
    this.groupId,
    this.groupAccessType,
    this.canRequestInvite,
    this.inviteOnly,
  });

  factory WorldInfo.fromJson(Map<String, dynamic> json) {
    return WorldInfo(
      name: json['name'] as String? ?? 'Unknown World',
      id: json['id'] as String? ?? 'unknown_id',
      instanceId: json['instanceId'] as String?,
      accessType: json['accessType'] as String?,
      region: json['region'] as String?,
      ownerId: json['ownerId'] as String?,
      groupId: json['groupId'] as String?,
      groupAccessType: json['groupAccessType'] as String?,
      canRequestInvite: json['canRequestInvite'] as bool?,
      inviteOnly: json['inviteOnly'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      if (instanceId != null) 'instanceId': instanceId,
      if (accessType != null) 'accessType': accessType,
      if (region != null) 'region': region,
      if (ownerId != null) 'ownerId': ownerId,
      if (groupId != null) 'groupId': groupId,
      if (groupAccessType != null) 'groupAccessType': groupAccessType,
      if (canRequestInvite != null) 'canRequestInvite': canRequestInvite,
      if (inviteOnly != null) 'inviteOnly': inviteOnly,
    };
  }
}

class Player {
  final String id;

  final String name;

  /// Player head position (for Resonite spatial tagging).
  final String? headPosition;

  /// Player head orientation (for Resonite spatial tagging).
  final String? headOrientation;

  Player({
    required this.id,
    required this.name,
    this.headPosition,
    this.headOrientation,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String? ?? 'unknown_id',
      name: json['name'] as String? ?? 'Unknown Player',
      headPosition: json['headPosition'] as String?,
      headOrientation: json['headOrientation'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (headPosition != null) 'headPosition': headPosition,
      if (headOrientation != null) 'headOrientation': headOrientation,
    };
  }
}

class LogMetadata {
  final WorldInfo? world;

  final List<Player> players;

  LogMetadata({this.world, this.players = const []});

  factory LogMetadata.fromJson(Map<String, dynamic> json) {
    return LogMetadata(
      world:
          json['world'] != null
              ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>)
              : null,
      players:
          (json['players'] as List<dynamic>?)
              ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (world != null) 'world': world!.toJson(),
      'players': players.map((e) => e.toJson()).toList(),
    };
  }
}
