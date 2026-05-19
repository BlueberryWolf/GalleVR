import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/models/config_model.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/tos_service.dart';
import '../../data/services/vrchat_service.dart';
import '../../core/services/update_service.dart';
import '../../core/services/connectivity_service.dart';
import '../widgets/tos_modal.dart';
import 'update_dialog.dart';

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

  // Connectivity monitoring related fields
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySubscription;

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

    // Start connectivity monitoring
    _startConnectivityMonitoring();
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

    // If Windows, check auto update setting
    if (Platform.isWindows) {
      final config = _appServiceManager.config;
      if (config != null && config.autoUpdateEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading GalleVR v$_latestVersion update automatically...'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 5),
          ),
        );
        _updateService.downloadAndInstall().catchError((e) {
          developer.log('Silent auto-update failed: $e', name: 'AppWrapper');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Auto-update failed. Click to download manually.'),
                backgroundColor: Colors.redAccent,
                action: SnackBarAction(
                  label: 'DOWNLOAD',
                  textColor: Colors.white,
                  onPressed: () => _updateService.openReleasesPage(),
                ),
              ),
            );
          }
        });
        return;
      } else {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(latestVersion: _latestVersion!),
        );
        return;
      }
    }

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
    _connectivitySubscription?.cancel();
    ConnectivityService().stopMonitoring();
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

  /// Start monitoring internet connectivity
  void _startConnectivityMonitoring() {
    final connectivityService = ConnectivityService();
    connectivityService.startMonitoring();
    
    // Set initial state
    _isOffline = !connectivityService.hasConnection;
    
    _connectivitySubscription = connectivityService.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isOffline = !isConnected;
        });
        
        if (!isConnected) {
          developer.log('App is offline', name: 'AppWrapper');
        } else {
          developer.log('App is online', name: 'AppWrapper');
          _checkTOSStatus();
        }
      }
    });
  }

  Widget _buildOfflineBanner() {
    final double bannerHeight = 60.0;
    final double topPadding = MediaQuery.of(context).padding.top;
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      left: 16,
      right: 16,
      top: _isOffline ? topPadding + 16 : -bannerHeight - 20,
      height: bannerHeight,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withAlpha(230),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFEF4444).withAlpha(128),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(102),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Internet is required to sync with VRChat.',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await ConnectivityService().checkConnectionManually();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(38),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'RETRY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        widget.child,

        // Offline Banner
        _buildOfflineBanner(),

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
