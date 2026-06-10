import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../models/verification_models.dart';
import '../models/photo_metadata.dart';
import '../models/log_metadata.dart';
import '../../core/isolate/isolate_worker_pool.dart';

// Service for interacting with the VRChat API
class VRChatService {
  late final VrchatDart _api;

  bool _isInitialized = false;

  // Cache for verification checks (5-minute TTL)
  static bool? _cachedIsVerified;
  static DateTime? _lastVerificationCheck;

  CurrentUser? get currentUser => _api.auth.currentUser;

  bool get isLoggedIn => currentUser != null;

  final PlatformService _platformService;

  VRChatService({PlatformService? platformService})
    : _platformService =
          platformService ?? PlatformServiceFactory.getPlatformService();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      developer.log('Initializing VRChat API client', name: 'VRChatService');

      final packageInfo = await PackageInfo.fromPlatform();
      await getApplicationDocumentsDirectory();

      _api = VrchatDart(
        userAgent: VrchatUserAgent(
          applicationName: 'GalleVR',
          version: packageInfo.version,
          contactInfo: 'https://github.com/BlueberryWolf/GalleVR',
        ),
        cookiePath: '${(await _platformService.getConfigDirectory())}/.cookies',
      );

      await _clearAuthCookies();
      await Future.delayed(Duration(milliseconds: 300));

      _isInitialized = true;
      developer.log(
        'VRChat API client initialized successfully',
        name: 'VRChatService',
      );
    } catch (e) {
      developer.log('Error initializing VRChat API: $e', name: 'VRChatService');
      rethrow;
    }
  }

  Future<void> _clearAuthCookies() async {
    try {
      developer.log('Clearing auth cookies', name: 'VRChatService');

      try {
        await _api.auth.logout();
      } catch (e) {
        developer.log(
          'Ignoring error during cookie cleanup: $e',
          name: 'VRChatService',
        );
      }

      await _clearCookiesFolder();

      if (_api.auth.currentUser != null) {
        developer.log('Forcing current user to null', name: 'VRChatService');
      }
    } catch (e) {
      developer.log('Error clearing auth cookies: $e', name: 'VRChatService');
    }
  }

  Future<LoginResult> login({
    required String username,
    required String password,
    String? totpCode,
  }) async {
    _cachedIsVerified = null;
    _lastVerificationCheck = null;

    if (!_isInitialized) {
      await initialize();
    }

    try {
      await _clearAuthCookies();

      try {
        await logout();
      } catch (e) {
        developer.log(
          'Ignoring error during logout: $e',
          name: 'VRChatService',
        );
      }

      developer.log(
        'Starting login for user: $username',
        name: 'VRChatService',
      );

      final loginResponse = await _api.auth.login(
        username: username,
        password: password,
      );

      if (loginResponse.failure != null) {
        developer.log(
          'Login failed: ${loginResponse.failure}',
          name: 'VRChatService',
        );
        return LoginResult(
          success: false,
          requiresTwoFactor: false,
          errorMessage: 'Login failed: ${loginResponse.failure}',
        );
      }

      final authResponse = loginResponse.success!.data;
      if (authResponse.requiresTwoFactorAuth) {
        developer.log(
          '2FA required for user: $username',
          name: 'VRChatService',
        );

        if (totpCode == null || totpCode.isEmpty) {
          return LoginResult(
            success: false,
            requiresTwoFactor: true,
            errorMessage: 'Two-factor authentication required',
          );
        }

        developer.log(
          'Verifying 2FA code for user: $username',
          name: 'VRChatService',
        );

        final twoFactorResponse = await _api.auth.verify2fa(totpCode);
        if (twoFactorResponse.failure != null) {
          developer.log(
            '2FA verification failed: ${twoFactorResponse.failure}',
            name: 'VRChatService',
          );
          return LoginResult(
            success: false,
            requiresTwoFactor: true,
            errorMessage: 'Invalid 2FA code',
          );
        }

        developer.log(
          '2FA verification successful for user: $username',
          name: 'VRChatService',
        );

        if (_api.auth.currentUser == null) {
          developer.log(
            'User still not logged in after 2FA verification',
            name: 'VRChatService',
          );
          return LoginResult(
            success: false,
            requiresTwoFactor: false,
            errorMessage: 'Failed to complete login after 2FA verification',
          );
        }
      }

      if (_api.auth.currentUser == null) {
        developer.log('User is null after login', name: 'VRChatService');
        return LoginResult(
          success: false,
          requiresTwoFactor: false,
          errorMessage: 'Login completed but user is null',
        );
      }

      developer.log(
        'Login successful for user: ${_api.auth.currentUser?.displayName}',
        name: 'VRChatService',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (_api.auth.currentUser == null) {
        developer.log(
          'Current user is still null after login',
          name: 'VRChatService',
        );
        return LoginResult(
          success: false,
          requiresTwoFactor: false,
          errorMessage: 'Login succeeded but user data is not available',
        );
      }

      developer.log(
        'Successfully verified user data access: ${_api.auth.currentUser!.displayName}',
        name: 'VRChatService',
      );

      return LoginResult(
        success: true,
        requiresTwoFactor: false,
        user: _api.auth.currentUser,
      );
    } catch (e) {
      developer.log('Error during login: $e', name: 'VRChatService');
      return LoginResult(
        success: false,
        requiresTwoFactor: false,
        errorMessage: 'Login error: $e',
      );
    }
  }

  Future<bool> logout() async {
    _cachedIsVerified = null;
    _lastVerificationCheck = null;

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await _api.auth.logout();

      await _clearCookiesFolder();

      return response.failure == null;
    } catch (e) {
      developer.log('Error logging out: $e', name: 'VRChatService');

      try {
        await _clearCookiesFolder();
      } catch (cookieError) {
        developer.log(
          'Error clearing cookies folder: $cookieError',
          name: 'VRChatService',
        );
      }

      return false;
    }
  }

  Future<void> _clearCookiesFolder() async {
    try {
      final configDir = await _platformService.getConfigDirectory();
      final cookiesDir = io.Directory('$configDir/.cookies');

      developer.log(
        'Checking for cookies folder at: ${cookiesDir.path}',
        name: 'VRChatService',
      );

      if (await cookiesDir.exists()) {
        developer.log(
          'Clearing cookies folder at: ${cookiesDir.path}',
          name: 'VRChatService',
        );

        final files = await cookiesDir.list().toList();

        for (final file in files) {
          if (file is io.File) {
            await file.delete();
            developer.log(
              'Deleted cookie file: ${file.path}',
              name: 'VRChatService',
            );
          }
        }

        developer.log(
          'Successfully cleared cookies folder',
          name: 'VRChatService',
        );
      } else {
        developer.log(
          'Cookies folder not found at: ${cookiesDir.path}',
          name: 'VRChatService',
        );
      }
    } catch (e) {
      developer.log('Error clearing cookies folder: $e', name: 'VRChatService');
    }
  }

  Future<List<LimitedUserFriend>> getFriends() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final friendsResponse =
          await _api.rawApi.getFriendsApi().getFriends().validateVrc();

      if (friendsResponse.failure != null) {
        throw Exception('Failed to get friends: ${friendsResponse.failure}');
      }

      return friendsResponse.success!.data;
    } catch (e) {
      developer.log('Error getting friends: $e', name: 'VRChatService');
      rethrow;
    }
  }

  Future<bool> updateStatusDescription(String newStatus) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!isLoggedIn) {
      throw Exception('Not logged in');
    }

    try {
      final userId = _api.auth.currentUser?.id;
      if (userId == null) {
        developer.log(
          'User ID is null when updating status description',
          name: 'VRChatService',
        );
        throw Exception('User ID is null');
      }

      developer.log(
        'Updating status to: $newStatus for user ID: $userId',
        name: 'VRChatService',
      );

      final response =
          await _api.rawApi
              .getUsersApi()
              .updateUser(
                userId: userId,
                updateUserRequest: UpdateUserRequest(
                  statusDescription: newStatus,
                ),
              )
              .validateVrc();

      if (response.failure == null) {
        developer.log(
          'Successfully updated status description for user ID: $userId',
          name: 'VRChatService',
        );
        return true;
      } else {
        developer.log(
          'Failed to update status: ${response.failure}',
          name: 'VRChatService',
        );
        return false;
      }
    } catch (e) {
      developer.log(
        'Error updating status description: $e',
        name: 'VRChatService',
      );
      return false;
    }
  }

  Future<String?> getCurrentStatusDescription() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!isLoggedIn) {
      developer.log(
        'Attempted to get status while not logged in',
        name: 'VRChatService',
      );
      throw Exception('Not logged in');
    }

    try {
      if (_api.auth.currentUser == null) {
        developer.log(
          'Current user is null when getting status',
          name: 'VRChatService',
        );
        throw Exception('Current user is null');
      }

      final statusDescription = _api.auth.currentUser!.statusDescription;
      developer.log(
        'Retrieved status directly from currentUser',
        name: 'VRChatService',
      );

      return statusDescription;
    } catch (e) {
      developer.log('Error getting current status: $e', name: 'VRChatService');
      return null;
    }
  }

  Future<VerificationResult> startAutomaticVerification({
    bool ageVerified = false,
    void Function(String message)? onProgress,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!isLoggedIn) {
      developer.log(
        'Attempted to start verification while not logged in',
        name: 'VRChatService',
      );
      return VerificationResult.failure('Not logged in');
    }

    if (_api.auth.currentUser == null) {
      developer.log(
        'Current user is null when starting verification',
        name: 'VRChatService',
      );
      return VerificationResult.failure('Current user is null');
    }

    try {
      final userId = currentUser?.id;
      if (userId == null) {
        developer.log(
          'User ID is null when starting verification',
          name: 'VRChatService',
        );
        return VerificationResult.failure('User ID is null');
      }

      onProgress?.call('Starting verification process...');
      developer.log(
        'Starting automatic verification for user: ${currentUser?.displayName} ($userId)',
        name: 'VRChatService',
      );

      try {
        const botId = 'usr_cfd81636-0ad1-4454-883e-e5c75ac9bafb';
        onProgress?.call('Verifying bot connection...');

        final statusRes =
            await _api.rawApi
                .getFriendsApi()
                .getFriendStatus(userId: botId)
                .validateVrc();
        bool isFriend = statusRes.success?.data.isFriend ?? false;

        if (!isFriend) {
          onProgress?.call('Connecting to GalleVR...');
          developer.log(
            'Sending client-side friend request to GalleVR ($botId)',
            name: 'VRChatService',
          );

          // silently try to friend the bot.
          await _api.rawApi.getFriendsApi().friend(userId: botId).validateVrc();

          // briefly wait for the server's websocket bot listener to automatically accept request
          for (int attempt = 1; attempt <= 3; attempt++) {
            await Future.delayed(const Duration(seconds: 2));
            final verifyRes =
                await _api.rawApi
                    .getFriendsApi()
                    .getFriendStatus(userId: botId)
                    .validateVrc();
            if (verifyRes.success?.data.isFriend == true) {
              developer.log(
                'Successfully automatically friended GalleVR bot locally',
                name: 'VRChatService',
              );
              break;
            }
          }
        }
      } catch (e) {
        developer.log(
          'Non-blocking bot connection logic completed with notice: $e',
          name: 'VRChatService',
        );
      }

      String originalStatus = '';
      try {
        onProgress?.call('Backing up your current status...');
        originalStatus = await getCurrentStatusDescription() ?? '';
        developer.log(
          'Successfully retrieved current status: $originalStatus',
          name: 'VRChatService',
        );
      } catch (e) {
        developer.log(
          'Error getting current status: $e',
          name: 'VRChatService',
        );
      }

      onProgress?.call('Requesting verification token...');
      developer.log(
        'Getting verification token from server for user ID: $userId',
        name: 'VRChatService',
      );

      final username = currentUser?.displayName;
      if (username == null) {
        return VerificationResult.failure('Username is null');
      }

      final verificationResponse = await _verifyWithServer(
        username,
        true,
        ageVerified: ageVerified,
      );

      if (verificationResponse == null) {
        return VerificationResult.failure('Failed to get verification token');
      }

      developer.log(
        'Successfully received verification token: ${verificationResponse.token}',
        name: 'VRChatService',
      );

      final authData = AuthData(
        accessKey: verificationResponse.accessKey,
        userId: verificationResponse.userId,
        ageVerified: verificationResponse.ageVerified,
      );

      onProgress?.call('Setting your VRChat status to token...');
      developer.log(
        'Updating status with verification token',
        name: 'VRChatService',
      );
      final statusUpdateSuccess = await updateStatusDescription(
        verificationResponse.token,
      );
      if (!statusUpdateSuccess) {
        return VerificationResult.failure(
          'Failed to update status with verification token',
        );
      }

      bool verificationSuccessful = false;
      const maxAttempts = 30;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        onProgress?.call(
          'Waiting for VRChat to sync (Attempt $attempt/$maxAttempts)...',
        );
        developer.log(
          'Checking verification status (attempt $attempt/$maxAttempts)',
          name: 'VRChatService',
        );

        final statusResult = await checkVerificationStatus(
          authData,
          forceRefresh: true,
        );
        if (statusResult) {
          verificationSuccessful = true;
          break;
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      onProgress?.call('Restoring your original status...');
      developer.log('Restoring original status', name: 'VRChatService');
      await updateStatusDescription(originalStatus);

      if (verificationSuccessful) {
        onProgress?.call('Verification successful!');
        developer.log('Verification successful', name: 'VRChatService');
        return VerificationResult.success(authData);
      } else {
        developer.log(
          'Verification failed after multiple attempts',
          name: 'VRChatService',
        );
        return VerificationResult.failure(
          'Verification failed after $maxAttempts attempts. VRChat API is being slow to update. Please try again in a minute.',
        );
      }
    } catch (e) {
      developer.log(
        'Error during automatic verification: $e',
        name: 'VRChatService',
      );
      return VerificationResult.failure('Verification error: $e');
    }
  }

  Future<VerificationResult> startManualVerification(
    String username, {
    bool ageVerified = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final verificationResponse = await _verifyWithServer(
        username,
        true,
        ageVerified: ageVerified,
      );

      if (verificationResponse == null) {
        return VerificationResult.failure('Failed to get verification token');
      }

      final authData = AuthData(
        accessKey: verificationResponse.accessKey,
        userId: verificationResponse.userId,
        ageVerified: verificationResponse.ageVerified,
      );

      return VerificationResult.success(
        authData,
        verificationToken: verificationResponse.token,
      );
    } catch (e) {
      developer.log(
        'Error during manual verification: $e',
        name: 'VRChatService',
      );
      return VerificationResult.failure('Verification error: $e');
    }
  }

  Future<Map<String, dynamic>?> lookupAccount(String identifier) async {
    try {
      final url = Uri.parse(
        'https://api.gallevr.app/vrchat/account-lookup/${Uri.encodeComponent(identifier)}',
      );

      developer.log(
        'Looking up user identifier: $identifier',
        name: 'VRChatService',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      developer.log('Account lookup request failed: $e', name: 'VRChatService');
      return null;
    }
  }

  Future<bool> checkVerificationStatus(
    AuthData authData, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedIsVerified == true &&
        _lastVerificationCheck != null &&
        now.difference(_lastVerificationCheck!) < const Duration(minutes: 5)) {
      developer.log(
        'Using cached verification status: $_cachedIsVerified',
        name: 'VRChatService',
      );
      return _cachedIsVerified!;
    }

    try {
      final url = Uri.parse(
        'https://api.gallevr.app/vrchat/verify/status/${authData.userId}',
      );
      developer.log(
        'Checking verification status for ${authData.userId} at URL: $url',
        name: 'VRChatService',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${authData.accessKey}',
          'Accept': 'application/json',
        },
      );

      developer.log(
        'Verification status response: ${response.statusCode} ${response.body}',
        name: 'VRChatService',
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final isVerified = responseData['status'] == 'verified';
        developer.log(
          'Verification status result: $isVerified',
          name: 'VRChatService',
        );

        if (isVerified) {
          _cachedIsVerified = true;
          _lastVerificationCheck = now;
          try {
            await fetchMe(authData, forceRefresh: true);
          } catch (e) {
            developer.log(
              'Error fetching profile after verification: $e',
              name: 'VRChatService',
            );
          }
        } else {
          _cachedIsVerified = null;
          _lastVerificationCheck = null;
        }

        return isVerified;
      }

      _cachedIsVerified = null;
      _lastVerificationCheck = null;
      return false;
    } catch (e) {
      developer.log(
        'Error checking verification status: $e',
        name: 'VRChatService',
      );
      _cachedIsVerified = null;
      _lastVerificationCheck = null;
      return false;
    }
  }

  Future<AuthData?> fetchMe(
    AuthData authData, {
    bool forceRefresh = false,
  }) async {
    try {
      final url = Uri.parse(
        'https://api.gallevr.app/vrchat/auth/me${forceRefresh ? '&cache=false' : ''}',
      );
      developer.log('Fetching user profile from $url', name: 'VRChatService');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${authData.accessKey}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final badges =
            (responseData['badges'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [];

        developer.log(
          'Received badges from API: $badges',
          name: 'VRChatService',
        );

        final updatedAuthData = AuthData(
          accessKey: authData.accessKey,
          userId: authData.userId,
          ageVerified: responseData['ageVerified'] == true,
          badges: badges,
          displayName:
              responseData['displayName'] as String? ??
              responseData['name'] as String?,
          avatarUrl:
              responseData['avatarUrl'] as String? ??
              responseData['pfp'] as String?,
        );

        await saveAuthData(updatedAuthData);
        developer.log(
          'Successfully fetched and saved updated auth data for ${updatedAuthData.displayName}',
          name: 'VRChatService',
        );
        return updatedAuthData;
      } else {
        developer.log(
          'Failed to fetch profile: ${response.statusCode} ${response.body}',
          name: 'VRChatService',
        );
      }
    } catch (e) {
      developer.log('Error fetching user profile: $e', name: 'VRChatService');
    }
    return null;
  }

  Future<List<PhotoMetadata>?> fetchPhotoList() async {
    try {
      final authData = await loadAuthData();
      if (authData == null) return null;

      final url = Uri.parse(
        'https://api.gallevr.app/vrchat/photo/list?user=${authData.userId}',
      );
      developer.log('Fetching photo list from $url', name: 'VRChatService');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${authData.accessKey}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return await IsolateWorkerPool().execute<String, List<PhotoMetadata>>(
          _parsePhotosTask,
          response.body,
        );
      } else {
        developer.log(
          'Failed to fetch photo list: ${response.statusCode} ${response.body}',
          name: 'VRChatService',
        );
      }
    } catch (e) {
      developer.log('Error fetching photo list: $e', name: 'VRChatService');
    }
    return null;
  }

  Future<bool> checkFriendStatus(String username) async {
    try {
      final url = Uri.parse(
        'https://api.gallevr.app/vrchat/friend-status/${Uri.encodeComponent(username)}',
      );
      developer.log(
        'Checking friend status for $username at URL: $url',
        name: 'VRChatService',
      );

      final response = await http.get(url);
      developer.log(
        'Friend status response: ${response.statusCode} ${response.body}',
        name: 'VRChatService',
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final isFriend = responseData['isFriend'] == true;
        developer.log('Friend status result: $isFriend', name: 'VRChatService');
        return isFriend;
      }

      return false;
    } catch (e) {
      developer.log('Error checking friend status: $e', name: 'VRChatService');
      return false;
    }
  }

  Future<bool> saveAuthData(AuthData authData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'gallevr_auth_data',
        json.encode(authData.toJson()),
      );
      return true;
    } catch (e) {
      developer.log('Error saving auth data: $e', name: 'VRChatService');
      return false;
    }
  }

  Future<AuthData?> loadAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authDataJson = prefs.getString('gallevr_auth_data');

      if (authDataJson == null) {
        return null;
      }

      return AuthData.fromJson(json.decode(authDataJson));
    } catch (e) {
      developer.log('Error loading auth data: $e', name: 'VRChatService');
      return null;
    }
  }

  Future<bool> setAgeVerified(bool verified) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gallevr_age_verified', verified);
      return true;
    } catch (e) {
      developer.log('Error saving age verification: $e', name: 'VRChatService');
      return false;
    }
  }

  Future<bool> loadAgeVerified() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isVerified = prefs.getBool('gallevr_age_verified') ?? false;

      if (!isVerified) {
        final authData = await loadAuthData();
        if (authData?.ageVerified ?? false) {
          await setAgeVerified(true);
          return true;
        }
      }

      return isVerified;
    } catch (e) {
      developer.log(
        'Error loading age verification: $e',
        name: 'VRChatService',
      );
      return false;
    }
  }

  Future<VerificationResponse?> _verifyWithServer(
    String userId,
    bool isManual, {
    bool ageVerified = false,
  }) async {
    try {
      final endpoint =
          isManual
              ? 'https://api.gallevr.app/vrchat/verify/manual'
              : 'https://api.gallevr.app/vrchat/verify';

      final body =
          isManual
              ? {'username': userId, 'ageVerified': ageVerified}
              : {'userId': userId, 'ageVerified': ageVerified};

      developer.log(
        'Making verification request to $endpoint with body: ${json.encode(body)}',
        name: 'VRChatService',
      );

      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          developer.log(
            'Verification request attempt $attempt/3',
            name: 'VRChatService',
          );

          final response = await http.post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          );

          developer.log(
            'Verification response: ${response.statusCode} ${response.body}',
            name: 'VRChatService',
          );

          if (response.statusCode == 200) {
            try {
              final responseData = json.decode(response.body);

              if (responseData['token'] == null ||
                  responseData['accessKey'] == null ||
                  responseData['userId'] == null) {
                developer.log(
                  'Verification response missing required fields: $responseData',
                  name: 'VRChatService',
                );

                if (attempt < 3) {
                  await Future.delayed(Duration(milliseconds: 500 * attempt));
                  continue;
                }
                return null;
              }

              developer.log(
                'Successfully received verification token',
                name: 'VRChatService',
              );
              return VerificationResponse(
                token: responseData['token'],
                accessKey: responseData['accessKey'],
                userId: responseData['userId'],
                ageVerified: responseData['ageVerified'] == true,
              );
            } catch (e) {
              developer.log(
                'Error parsing verification response: $e',
                name: 'VRChatService',
              );
              if (attempt < 3) {
                await Future.delayed(Duration(milliseconds: 500 * attempt));
                continue;
              }
              return null;
            }
          } else {
            developer.log(
              'Verification request failed: ${response.statusCode} ${response.body}',
              name: 'VRChatService',
            );

            if (attempt < 3) {
              await Future.delayed(Duration(milliseconds: 500 * attempt));
              continue;
            }
          }
        } catch (e) {
          developer.log(
            'Error during verification request attempt $attempt: $e',
            name: 'VRChatService',
          );

          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
        }
      }

      return null;
    } catch (e) {
      developer.log(
        'Error making verification request: $e',
        name: 'VRChatService',
      );
      return null;
    }
  }

  Future<AuthData?> pairWithCode(String code) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.gallevr.app/vrchat/pair/verify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'code': code}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true &&
            data['accessKey'] != null &&
            data['userId'] != null) {
          final authData = AuthData(
            accessKey: data['accessKey'],
            userId: data['userId'],
            ageVerified: true,
            displayName: data['displayName'],
            avatarUrl: data['avatarUrl'],
          );

          await saveAuthData(authData);
          return authData;
        }
      }
      return null;
    } catch (e) {
      developer.log('Error pairing with code: $e', name: 'VRChatService');
      return null;
    }
  }
}

class LoginResult {
  final bool success;

  final bool requiresTwoFactor;

  final String? errorMessage;

  final CurrentUser? user;

  LoginResult({
    required this.success,
    required this.requiresTwoFactor,
    this.errorMessage,
    this.user,
  });
}

List<PhotoMetadata> _parsePhotosTask(String jsonBody) {
  final List<dynamic> responseData = json.decode(jsonBody);
  return responseData
      .map((json) {
        try {
          final metadataJson = json['metadata'] as Map<String, dynamic>;
          final rawTakenDate = metadataJson['takenDate'];
          int takenDateMs = DateTime.now().millisecondsSinceEpoch;

          if (rawTakenDate is int) {
            takenDateMs = rawTakenDate;
          } else if (rawTakenDate is String) {
            final parsed = DateTime.tryParse(rawTakenDate);
            if (parsed != null) {
              takenDateMs = parsed.millisecondsSinceEpoch;
            }
          }

          final photoId = json['id'] as String?;
          final userId = json['userId'] as String?;
          String? resolvedUrl = json['url'] as String?;

          if (photoId != null) {
            resolvedUrl = 'https://gallevr.app/p/$photoId';
          }

          return PhotoMetadata(
            takenDate: takenDateMs,
            filename: (metadataJson['filename'] as String? ?? 'unknown.png')
                .replaceAll('.webp', '.png'),
            galleryUrl: resolvedUrl,
            remoteId: photoId,
            views: metadataJson['views'] as int? ?? 0,
            isEdited: metadataJson['isEdited'] == true,
            world:
                metadataJson['world'] != null
                    ? WorldInfo.fromJson(
                      metadataJson['world'] as Map<String, dynamic>,
                    )
                    : null,
            players:
                (metadataJson['players'] as List<dynamic>?)
                    ?.map((p) => Player.fromJson(p as Map<String, dynamic>))
                    .toList() ??
                [],
          );
        } catch (e) {
          developer.log(
            'Skipping corrupt backend photo object: $e',
            name: 'VRChatService',
          );
          return null;
        }
      })
      .whereType<PhotoMetadata>()
      .toList();
}
