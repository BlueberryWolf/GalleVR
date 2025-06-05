// Model for world information from VRChat logs
class WorldInfo {
  // World name
  final String name;
  
  // World ID
  final String id;
  
  // Instance ID
  final String? instanceId;
  
  // Access type (public, friends+, etc.)
  final String? accessType;
  
  // Region
  final String? region;
  
  // Owner ID
  final String? ownerId;
  
  // Group ID
  final String? groupId;
  
  // Group access type
  final String? groupAccessType;
  
  // Whether users can request invites
  final bool? canRequestInvite;

  // Whether the instance is invite only
  final bool? inviteOnly;

  // Default constructor
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

  // Create a WorldInfo from JSON
  factory WorldInfo.fromJson(Map<String, dynamic> json) {
    return WorldInfo(
      name: json['name'] as String,
      id: json['id'] as String,
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

  // Convert WorldInfo to JSON
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

// Model for player information from VRChat logs
class Player {
  // Player ID
  final String id;
  
  // Player display name
  final String name;

  // Default constructor
  Player({
    required this.id,
    required this.name,
  });

  // Create a Player from JSON
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  // Convert Player to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

// Model for metadata extracted from VRChat logs
class LogMetadata {
  // World information
  final WorldInfo? world;
  
  // List of players in the world
  final List<Player> players;

  // Default constructor
  LogMetadata({
    this.world,
    this.players = const [],
  });

  // Create a LogMetadata from JSON
  factory LogMetadata.fromJson(Map<String, dynamic> json) {
    return LogMetadata(
      world: json['world'] != null 
          ? WorldInfo.fromJson(json['world'] as Map<String, dynamic>) 
          : null,
      players: (json['players'] as List<dynamic>?)
          ?.map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  // Convert LogMetadata to JSON
  Map<String, dynamic> toJson() {
    return {
      if (world != null) 'world': world!.toJson(),
      'players': players.map((e) => e.toJson()).toList(),
    };
  }
}
