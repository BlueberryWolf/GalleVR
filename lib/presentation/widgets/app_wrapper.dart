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
import '../theme/app_theme.dart';

class AppWrapper extends StatefulWidget {
  final Widget child;

  const AppWrapper({super.key, required this.child});

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

  String? _appVersion;
  String? _latestVersion;
  StreamSubscription<bool>? _updateSubscription;

  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySubscription;

  bool _previousUploadEnabled = true;
  bool _wasUploadDisabledByTOS = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _appServiceManager.configStream.listen((config) {
      if (config.uploadEnabled && _wasUploadDisabledByTOS) {
        _showTOSPromptAndDisableUpload(config);
      }
    });

    _updateSubscription = _updateService.updateAvailableStream.listen((
      hasUpdate,
    ) {
      if (mounted) {
        setState(() {
          _latestVersion = _updateService.latestVersion;
        });

        if (hasUpdate && _latestVersion != null) {
          _showUpdateNotification();
        }
      }
    });

    _loadAppVersion();

    _checkTOSStatus();

    _startConnectivityMonitoring();
  }

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

  String? _lastNotifiedVersion;

  void _showUpdateNotification() {
    if (!mounted) return;

    if (_lastNotifiedVersion == _latestVersion) {
      developer.log(
        'Already showed in-app notification for version $_latestVersion, skipping',
        name: 'AppWrapper',
      );
      return;
    }

    _lastNotifiedVersion = _latestVersion;

    if (Platform.isWindows) {
      final config = _appServiceManager.config;
      if (config != null && config.autoUpdateEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloading GalleVR v$_latestVersion update automatically...',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 5),
          ),
        );
        _updateService.downloadAndInstall().catchError((e) {
          developer.log('Silent auto-update failed: $e', name: 'AppWrapper');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Auto-update failed. Click to download manually.',
                ),
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
            developer.log(
              'Download button clicked in in-app notification',
              name: 'AppWrapper',
            );
          }
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    developer.log(
      'Showed in-app notification for version $_latestVersion',
      name: 'AppWrapper',
    );
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
    if (state == AppLifecycleState.resumed) {
      _checkTOSStatus();
    }
  }

  Future<void> _showTOSPromptAndDisableUpload(ConfigModel config) async {
    if (_appServiceManager.isTOSModalVisible) {
      developer.log(
        'TOS modal is already visible, skipping',
        name: 'AppWrapper',
      );
      return;
    }

    _previousUploadEnabled = config.uploadEnabled;

    final updatedConfig = config.copyWith(uploadEnabled: false);
    await _configRepository.saveConfig(updatedConfig);

    await _appServiceManager.updateConfig(updatedConfig);

    _wasUploadDisabledByTOS = true;

    if (mounted) {
      _appServiceManager.isTOSModalVisible = true;

      setState(() {
        _showTOSModal = true;
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo uploading has been disabled until you accept the Terms of Service.',
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _checkTOSStatus() async {
    if (_isCheckingTOS) return;

    _isCheckingTOS = true;
    try {
      final authData = await _vrchatService.loadAuthData();
      final isAuthenticated = authData != null;

      if (isAuthenticated) {
        final needsToAcceptTOS = await _tosService.needsToAcceptTOS();

        if (needsToAcceptTOS) {
          final config = await _configRepository.loadConfig();

          if (_appServiceManager.isTOSModalVisible) {
            developer.log(
              'TOS modal is already visible, skipping',
              name: 'AppWrapper',
            );
            return;
          }

          if (config.uploadEnabled) {
            await _showTOSPromptAndDisableUpload(config);
          } else {
            if (mounted) {
              _appServiceManager.isTOSModalVisible = true;

              setState(() {
                _showTOSModal = true;
              });
            }
          }
        }

        if (mounted) {}
      } else {
        if (mounted) {
          setState(() {
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

    _appServiceManager.isTOSModalVisible = false;

    if (_wasUploadDisabledByTOS) {
      try {
        final config = await _configRepository.loadConfig();

        final updatedConfig = config.copyWith(
          uploadEnabled: _previousUploadEnabled,
        );
        await _configRepository.saveConfig(updatedConfig);

        await _appServiceManager.updateConfig(updatedConfig);

        _wasUploadDisabledByTOS = false;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _previousUploadEnabled
                  ? 'Terms of Service accepted. Photo uploading has been re-enabled.'
                  : 'Terms of Service accepted. You can now enable photo uploading in settings.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        developer.log('Error restoring upload setting: $e', name: 'AppWrapper');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terms of Service accepted, but there was an error restoring your upload settings.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Terms of Service accepted. You can now upload photos.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    _appServiceManager.isTOSModalVisible = false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You must accept the Terms of Service to upload photos.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _startConnectivityMonitoring() {
    final connectivityService = ConnectivityService();
    connectivityService.startMonitoring();

    _isOffline = !connectivityService.hasConnection;

    _connectivitySubscription = connectivityService.connectionStream.listen((
      isConnected,
    ) {
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
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
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
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 24),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
                child: const Text(
                  'RETRY',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
        widget.child,

        _buildOfflineBanner(),

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
