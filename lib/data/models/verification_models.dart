import 'package:equatable/equatable.dart';

// Verification method enum
enum VerificationMethod {
  // Automatic verification using VRChat login
  automatic,

  // Manual verification by adding GalleVR as a friend
  manual,
}

// Verification status enum
enum VerificationStatus {
  // Not verified
  notVerified,

  // Verification in progress
  inProgress,

  // Verification successful
  verified,

  // Verification failed
  failed,
}

// Response from the verification API
class VerificationResponse extends Equatable {
  // Verification token to be added to user's bio
  final String token;

  // Access key for the GalleVR API
  final String accessKey;

  // User ID
  final String userId;

  // Whether the user is verified as over 13 years old
  final bool ageVerified;

  // Default constructor
  const VerificationResponse({
    required this.token,
    required this.accessKey,
    required this.userId,
    this.ageVerified = false,
  });

  // Create a VerificationResponse from JSON
  factory VerificationResponse.fromJson(Map<String, dynamic> json) {
    return VerificationResponse(
      token: json['token'] as String,
      accessKey: json['accessKey'] as String,
      userId: json['userId'] as String,
      ageVerified: json['ageVerified'] as bool? ?? false,
    );
  }

  // Convert VerificationResponse to JSON
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

// Authentication data for GalleVR
class AuthData extends Equatable {
  // Access key for the GalleVR API
  final String accessKey;

  // User ID
  final String userId;

  // Whether the user is verified as over 13 years old
  final bool ageVerified;

  // Default constructor
  const AuthData({
    required this.accessKey,
    required this.userId,
    this.ageVerified = false,
  });

  // Create an AuthData from JSON
  factory AuthData.fromJson(Map<String, dynamic> json) {
    return AuthData(
      accessKey: json['accessKey'] as String,
      userId: json['userId'] as String,
      ageVerified: json['ageVerified'] as bool? ?? false,
    );
  }

  // Convert AuthData to JSON
  Map<String, dynamic> toJson() {
    return {
      'accessKey': accessKey,
      'userId': userId,
      'ageVerified': ageVerified,
    };
  }

  @override
  List<Object?> get props => [accessKey, userId, ageVerified];
}

// Result of a verification attempt
class VerificationResult extends Equatable {
  // Whether the verification was successful
  final bool success;

  // Error message if verification failed
  final String? errorMessage;

  // Authentication data if verification was successful
  final AuthData? authData;

  // Verification status
  final VerificationStatus status;

  // Verification token for manual verification
  final String? verificationToken;

  // Whether the user is verified as over 13 years old
  final bool ageVerified;

  // Default constructor
  const VerificationResult({
    required this.success,
    this.errorMessage,
    this.authData,
    required this.status,
    this.verificationToken,
    this.ageVerified = false,
  });

  // Create a success result
  factory VerificationResult.success(AuthData authData, {String? verificationToken}) {
    return VerificationResult(
      success: true,
      authData: authData,
      status: VerificationStatus.verified,
      verificationToken: verificationToken,
      ageVerified: authData.ageVerified,
    );
  }

  // Create a failure result
  factory VerificationResult.failure(String errorMessage) {
    return VerificationResult(
      success: false,
      errorMessage: errorMessage,
      status: VerificationStatus.failed,
    );
  }

  // Create an in-progress result
  factory VerificationResult.inProgress() {
    return const VerificationResult(
      success: false,
      status: VerificationStatus.inProgress,
    );
  }

  @override
  List<Object?> get props => [success, errorMessage, authData, status, verificationToken, ageVerified];
}
