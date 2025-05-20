import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/verification_models.dart';
import 'vrchat_service.dart';

class TOSService {
  final VRChatService _vrchatService;

  // Keys for storing TOS data in SharedPreferences
  static const String _lastAcceptedVersionKey = 'last_accepted_tos_version';
  static const String _lastAcceptedDateKey = 'last_accepted_tos_date';

  // API endpoints
  static const String _tosStatusEndpoint = 'https://api.blueberry.coffee/vrchat/tos/status';
  static const String _tosAcceptEndpoint = 'https://api.blueberry.coffee/vrchat/tos/accept';
  static const String _tosContentEndpoint = 'https://api.blueberry.coffee/vrchat/tos';

  TOSService({VRChatService? vrchatService})
      : _vrchatService = vrchatService ?? VRChatService();

  /// Check if the user needs to accept the latest TOS
  /// Returns true if the user needs to accept the TOS, false otherwise
  Future<bool> needsToAcceptTOS() async {
    try {
      final authData = await _vrchatService.loadAuthData();
      if (authData == null) {
        // No auth data, so no need to check TOS
        return false;
      }

      final statusResponse = await _getTOSStatus(authData);
      return statusResponse['needsToAccept'] ?? false;
    } catch (e) {
      developer.log('Error checking TOS status: $e', name: 'TOSService');
      // In case of error, assume no need to accept to avoid blocking the user
      return false;
    }
  }

  /// Get the TOS content from the server
  Future<Map<String, dynamic>> getTOSContent() async {
    try {
      final response = await http.get(Uri.parse(_tosContentEndpoint));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load TOS content: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error fetching TOS content: $e', name: 'TOSService');
      // Return a basic error message as content
      return {
        'content': {
          'message': 'Unable to load Terms of Service. Please try again later.'
        },
        'lastModified': DateTime.now().toIso8601String()
      };
    }
  }

  /// Accept the current TOS version
  Future<bool> acceptTOS() async {
    try {
      final authData = await _vrchatService.loadAuthData();
      if (authData == null) {
        throw Exception('No authentication data found');
      }

      final response = await http.post(
        Uri.parse(_tosAcceptEndpoint),
        headers: {
          'Authorization': 'Bearer ${authData.accessKey}',
          'Content-Type': 'application/json'
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        // Save the accepted version locally
        await _saveAcceptedVersion(result['version']);

        return true;
      } else {
        throw Exception('Failed to accept TOS: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error accepting TOS: $e', name: 'TOSService');
      return false;
    }
  }

  /// Get the TOS status from the server
  Future<Map<String, dynamic>> _getTOSStatus(AuthData authData) async {
    final response = await http.get(
      Uri.parse(_tosStatusEndpoint),
      headers: {
        'Authorization': 'Bearer ${authData.accessKey}'
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check TOS status: ${response.statusCode}');
    }
  }

  /// Save the accepted TOS version locally
  Future<void> _saveAcceptedVersion(int version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastAcceptedVersionKey, version);
      await prefs.setString(_lastAcceptedDateKey, DateTime.now().toIso8601String());

      developer.log('Saved accepted TOS version: $version', name: 'TOSService');
    } catch (e) {
      developer.log('Error saving accepted TOS version: $e', name: 'TOSService');
    }
  }

  /// Get the locally stored last accepted TOS version
  Future<int> getLastAcceptedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_lastAcceptedVersionKey) ?? 0;
    } catch (e) {
      developer.log('Error getting last accepted TOS version: $e', name: 'TOSService');
      return 0;
    }
  }
}
