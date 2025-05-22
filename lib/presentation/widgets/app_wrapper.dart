import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/models/config_model.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/tos_service.dart';
import '../../data/services/vrchat_service.dart';
import '../../core/services/update_service.dart';
import '../widgets/tos_modal.dart';

/// A widget that wraps the entire app and handles global functionality
/// such as showing the TOS modal when needed.
class AppWrapper extends StatefulWidget {
  final Widget child;

  const AppWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with WidgetsBindingObserver {
  final TOSService _tosService = TOSService();
  final VRChatService _vrchatService = VRChatService();
  final ConfigRepository _configRepository = ConfigRepository();
  final AppServiceManager _appServiceManager = AppServiceManager();
  final UpdateService _updateService = UpdateService();

  bool _showTOSModal = false;
  bool _isCheckingTOS = false;
  bool _isAuthenticated = false;

  // Update notification related fields
  String? _appVersion;
  String? _latestVersion;
  bool _updateAvailable = false;
  StreamSubscription<bool>? _updateSubscription;

  // Track the previous upload setting before TOS check
  bool _previousUploadEnabled = true;
  bool _wasUploadDisabledByTOS = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for config changes
    _appServiceManager.configStream.listen((config) {
      // If upload was enabled and TOS needs acceptance, disable it
      if (config.uploadEnabled && _wasUploadDisabledByTOS) {
        _showTOSPromptAndDisableUpload(config);
      }
    });

    // Listen for update notifications
    _updateSubscription = _updateService.updateAvailableStream.listen((hasUpdate) {
      if (mounted) {
        setState(() {
          _updateAvailable = hasUpdate;
          _latestVersion = _updateService.latestVersion;
        });

        // Show in-app notification when update is available
        if (hasUpdate && _latestVersion != null) {
          _showUpdateNotification();
        }
      }
    });

    // Load app version
    _loadAppVersion();

    _checkTOSStatus();
  }

  /// Load the current app version
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
      developer.log('App version loaded: $_appVersion', name: 'AppWrapper');
    } catch (e) {
      developer.log('Error loading app version: $e', name: 'AppWrapper');
    }
  }

  // Track the last version we showed a notification for
  String? _lastNotifiedVersion;

  /// Show an in-app notification about available updates
  void _showUpdateNotification() {
    if (!mounted) return;

    // Check if we've already shown a notification for this version
    if (_lastNotifiedVersion == _latestVersion) {
      developer.log('Already showed in-app notification for version $_latestVersion, skipping',
          name: 'AppWrapper');
      return;
    }

    // Remember this version
    _lastNotifiedVersion = _latestVersion;

    // Show a snackbar with the update notification
    final snackBar = SnackBar(
      content: Text('A new version ($_latestVersion) is available!'),
      backgroundColor: Theme.of(context).colorScheme.primary,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'DOWNLOAD',
        textColor: Colors.white,
        onPressed: () async {
          if (mounted) {
            await _updateService.openReleasesPage();
            developer.log('Download button clicked in in-app notification', name: 'AppWrapper');
          }
        },
      ),
    );

    // Show the snackbar
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    developer.log('Showed in-app notification for version $_latestVersion', name: 'AppWrapper');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Check TOS status when app resumes
    if (state == AppLifecycleState.resumed) {
      _checkTOSStatus();
    }
  }

  /// Show TOS prompt and disable upload if needed
  Future<void> _showTOSPromptAndDisableUpload(ConfigModel config) async {
    // Check if a TOS modal is already visible
    if (_appServiceManager.isTOSModalVisible) {
      developer.log('TOS modal is already visible, skipping', name: 'AppWrapper');
      return;
    }

    // Save the current upload setting
    _previousUploadEnabled = config.uploadEnabled;

    // Disable uploading
    final updatedConfig = config.copyWith(uploadEnabled: false);
    await _configRepository.saveConfig(updatedConfig);

    // Notify the app service manager about the config change
    await _appServiceManager.updateConfig(updatedConfig);

    // Mark that we disabled uploading due to TOS
    _wasUploadDisabledByTOS = true;

    // Show the TOS modal
    if (mounted) {
      // Set the global flag
      _appServiceManager.isTOSModalVisible = true;

      setState(() {
        _showTOSModal = true;
      });
    }

    // Show a message to the user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo uploading has been disabled until you accept the Terms of Service.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Check if the user needs to accept the TOS
  Future<void> _checkTOSStatus() async {
    if (_isCheckingTOS) return;

    _isCheckingTOS = true;
    try {
      // Check if user is authenticated
      final authData = await _vrchatService.loadAuthData();
      final isAuthenticated = authData != null;

      if (isAuthenticated) {
        // Check if user needs to accept TOS
        final needsToAcceptTOS = await _tosService.needsToAcceptTOS();

        if (needsToAcceptTOS) {
          // Get current config
          final config = await _configRepository.loadConfig();

          // Check if a TOS modal is already visible
          if (_appServiceManager.isTOSModalVisible) {
            developer.log('TOS modal is already visible, skipping', name: 'AppWrapper');
            return;
          }

          // If uploading is enabled, disable it and show TOS
          if (config.uploadEnabled) {
            await _showTOSPromptAndDisableUpload(config);
          } else {
            // Just show the TOS modal
            if (mounted) {
              // Set the global flag
              _appServiceManager.isTOSModalVisible = true;

              setState(() {
                _showTOSModal = true;
              });
            }
          }
        }

        if (mounted) {
          setState(() {
            _isAuthenticated = isAuthenticated;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _showTOSModal = false;
            _wasUploadDisabledByTOS = false;
          });
        }
      }
    } catch (e) {
      developer.log('Error checking TOS status: $e', name: 'AppWrapper');
    } finally {
      _isCheckingTOS = false;
    }
  }

  void _handleTOSAccept() async {
    setState(() {
      _showTOSModal = false;
    });

    // Reset the global flag
    _appServiceManager.isTOSModalVisible = false;

    // Re-enable uploading if it was disabled due to TOS
    if (_wasUploadDisabledByTOS) {
      try {
        // Get current config
        final config = await _configRepository.loadConfig();

        // Restore previous upload setting
        final updatedConfig = config.copyWith(uploadEnabled: _previousUploadEnabled);
        await _configRepository.saveConfig(updatedConfig);

        // Notify the app service manager about the config change
        await _appServiceManager.updateConfig(updatedConfig);

        // Reset the flag
        _wasUploadDisabledByTOS = false;

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_previousUploadEnabled
              ? 'Terms of Service accepted. Photo uploading has been re-enabled.'
              : 'Terms of Service accepted. You can now enable photo uploading in settings.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        developer.log('Error restoring upload setting: $e', name: 'AppWrapper');

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terms of Service accepted, but there was an error restoring your upload settings.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terms of Service accepted. You can now upload photos.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    // Reset the global flag
    _appServiceManager.isTOSModalVisible = false;

    // Show warning message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You must accept the Terms of Service to upload photos.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        widget.child,

        // TOS Modal
        if (_showTOSModal)
          TOSModal(
            onAccept: _handleTOSAccept,
            onDecline: _handleTOSDecline,
            title: 'Terms of Service',
          ),
      ],
    );
  }
}
