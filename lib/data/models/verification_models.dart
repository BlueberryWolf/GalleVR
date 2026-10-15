import 'package:equatable/equatable.dart';

enum VerificationMethod {
  /// Automatic verification using VRChat login.
  automatic,

  /// Manual verification by adding GalleVR as a friend.
  manual,

  /// Link via instantaneous numerical pair code from existing web session.
  pairCode,
}

enum VerificationStatus { notVerified, inProgress, verified, failed }

class VerificationResponse extends Equatable {
  /// Token the user adds to their VRChat bio.
  final String token;

  final String accessKey;

  final String userId;

  /// Whether the user is verified as over 13 years old.
  final bool ageVerified;

  const VerificationResponse({
    required this.token,
    required this.accessKey,
    required this.userId,
    this.ageVerified = false,
  });

  factory VerificationResponse.fromJson(Map<String, dynamic> json) {
    return VerificationResponse(
      token: json['token'] as String,
      accessKey: json['accessKey'] as String,
      userId: json['userId'] as String,
      ageVerified: json['ageVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'accessKey': accessKey,
      'userId': userId,
      'ageVerified': ageVerified,
    };
  }

  @override
  List<Object?> get props => [token, accessKey, userId, ageVerified];
}

class AuthData extends Equatable {
  final String accessKey;

  final String userId;

  /// Whether the user is verified as over 13 years old.
  final bool ageVerified;

  final List<String> badges;

  final String? displayName;
  final String? avatarUrl;

  const AuthData({
    required this.accessKey,
    required this.userId,
    this.ageVerified = false,
    this.badges = const [],
    this.displayName,
    this.avatarUrl,
  });

  factory AuthData.fromJson(Map<String, dynamic> json) {
    return AuthData(
      accessKey: json['accessKey'] as String,
      userId: json['userId'] as String,
      ageVerified: json['ageVerified'] as bool? ?? false,
      badges:
          (json['badges'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      displayName: json['displayName'] as String? ?? json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String? ?? json['pfp'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessKey': accessKey,
      'userId': userId,
      'ageVerified': ageVerified,
      'badges': badges,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
    };
  }

  @override
  List<Object?> get props => [
    accessKey,
    userId,
    ageVerified,
    badges,
    displayName,
    avatarUrl,
  ];

  /// Highest supporter tier among the user's badges.
  SupporterTier get supporterTier {
    final lowerBadges = badges.map((b) => b.toLowerCase()).toList();

    if (lowerBadges.contains('mega_supporter')) {
      return SupporterTier.megaSupporter;
    }

    if (lowerBadges.contains('super_supporter')) {
      return SupporterTier.superSupporter;
    }

    if (lowerBadges.contains('supporter') || lowerBadges.contains('donator')) {
      return SupporterTier.supporter;
    }

    return SupporterTier.none;
  }

  bool get isEditor {
    final lowerBadges = badges.map((b) => b.toLowerCase()).toList();
    return lowerBadges.contains('editor') ||
        lowerBadges.contains('admin') ||
        lowerBadges.contains('furality_team') ||
        lowerBadges.contains('owner');
  }
}

enum SupporterTier { none, supporter, superSupporter, megaSupporter }

extension SupporterTierExtension on SupporterTier {
  String get name {
    switch (this) {
      case SupporterTier.megaSupporter:
        return 'Mega Supporter';
      case SupporterTier.superSupporter:
        return 'Super Supporter';
      case SupporterTier.supporter:
        return 'Supporter';
      case SupporterTier.none:
        return 'Standard User';
    }
  }

  dynamic get color {
    switch (this) {
      case SupporterTier.megaSupporter:
        return 0xFFB884FC;
      case SupporterTier.superSupporter:
        return 0xFFFFD700;
      case SupporterTier.supporter:
        return 0xFF4CAF50;
      case SupporterTier.none:
        return null;
    }
  }
}

class VerificationResult extends Equatable {
  final bool success;

  final String? errorMessage;

  final AuthData? authData;

  final VerificationStatus status;

  /// Token the user adds to their VRChat bio.
  final String? verificationToken;

  /// Whether the user is verified as over 13 years old.
  final bool ageVerified;

  const VerificationResult({
    required this.success,
    this.errorMessage,
    this.authData,
    required this.status,
    this.verificationToken,
    this.ageVerified = false,
  });

  factory VerificationResult.success(
    AuthData authData, {
    String? verificationToken,
  }) {
    return VerificationResult(
      success: true,
      authData: authData,
      status: VerificationStatus.verified,
      verificationToken: verificationToken,
      ageVerified: authData.ageVerified,
    );
  }

  factory VerificationResult.failure(String errorMessage) {
    return VerificationResult(
      success: false,
      errorMessage: errorMessage,
      status: VerificationStatus.failed,
    );
  }

  factory VerificationResult.inProgress() {
    return const VerificationResult(
      success: false,
      status: VerificationStatus.inProgress,
    );
  }

  @override
  List<Object?> get props => [
    success,
    errorMessage,
    authData,
    status,
    verificationToken,
    ageVerified,
  ];
}
