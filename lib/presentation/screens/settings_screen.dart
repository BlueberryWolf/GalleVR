import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:developer' as developer;
import 'package:path/path.dart' as path;
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/repositories/config_repository.dart';
import '../../data/models/config_model.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/tos_service.dart';
import '../../core/platform/platform_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/update_service.dart';
import '../../core/services/vrchat_registry_service.dart';
import '../widgets/tos_modal.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigRepository _configRepository = ConfigRepository();
  final PlatformService _platformService =
      PlatformServiceFactory.getPlatformService();
  final ScrollController _scrollController = ScrollController();
  final UpdateService _updateService = UpdateService();
  final TOSService _tosService = TOSService();
  final VRChatRegistryService _vrchatRegistryService = VRChatRegistryService();

  ConfigModel? _config;
  bool _isLoading = true;
  String _appVersion = '1.0.0'; // Default version
  bool _updateAvailable = false;
  String? _latestVersion;
  bool _showTOSModal = false;

  // Stream subscription for update status
  late StreamSubscription<bool>? _updateSubscription;

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadAppVersion();

    // Listen for update status changes
    _updateSubscription = _updateService.updateAvailableStream.listen((hasUpdate) {
      if (mounted) {
        setState(() {
          _updateAvailable = hasUpdate;
          _latestVersion = _updateService.latestVersion;
        });
      }
    });

    // Listen for config changes from other parts of the app
    AppServiceManager().configStream.listen((updatedConfig) {
      if (mounted && _config != null && _config!.uploadEnabled != updatedConfig.uploadEnabled) {
        setState(() {
          _config = updatedConfig;
        });
      }
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
      });
      developer.log('App version loaded: $_appVersion', name: 'SettingsScreen');
    } catch (e) {
      developer.log(
        'Error loading app version: $e',
        name: 'SettingsScreen',
        error: e,
      );
    }
  }

  /// Check for updates
  /// Now uses forceCheckForUpdates to ensure update check happens every time
  Future<void> _checkForUpdates() async {
    try {
      developer.log('Manually checking for updates...', name: 'SettingsScreen');
      final hasUpdate = await _updateService.forceCheckForUpdates();
      if (mounted) {
        setState(() {
          _updateAvailable = hasUpdate;
          _latestVersion = _updateService.latestVersion;
        });
      }
      developer.log('Update check completed. Update available: $_updateAvailable, Latest version: $_latestVersion',
          name: 'SettingsScreen');
    } catch (e) {
      developer.log('Error checking for updates: $e', name: 'SettingsScreen');
    }
  }

  /// Check for updates with UI feedback
  Future<void> _checkForUpdatesWithFeedback() async {
    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking for updates...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    // Check for updates
    await _checkForUpdates();

    // Show result
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _updateAvailable
            ? Text('Update available! Version $_latestVersion is ready to download.')
            : const Text('You have the latest version.'),
          backgroundColor: _updateAvailable
            ? Theme.of(context).colorScheme.primary
            : Colors.green,
          duration: const Duration(seconds: 3),
          action: _updateAvailable ? SnackBarAction(
            label: 'DOWNLOAD',
            textColor: Colors.white,
            onPressed: () {
              _updateService.openReleasesPage();
            },
          ) : null,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _updateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });

    try {
      developer.log('Loading config...', name: 'SettingsScreen');
      final config = await _configRepository.loadConfig();
      developer.log('Config loaded successfully', name: 'SettingsScreen');
      setState(() {
        _config = config;
        _isLoading = false;
      });
    } catch (e) {
      developer.log(
        'Error loading config: $e',
        name: 'SettingsScreen',
        error: e,
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig(ConfigModel config) async {
    final double currentScrollPosition =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    if (_config != config) {
      setState(() {
        _config = config;
      });
    }

    try {
      await _configRepository.saveConfig(config);

      await AppServiceManager().updateConfig(config);

      developer.log(
        'Config saved and services updated',
        name: 'SettingsScreen',
      );
    } catch (e) {
      developer.log(
        'Error saving config: $e',
        name: 'SettingsScreen',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving settings: $e')));
      }
    } finally {
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              currentScrollPosition <=
                  _scrollController.position.maxScrollExtent) {
            _scrollController.jumpTo(currentScrollPosition);
          }
        });
      }
    }
  }

  void _handleTOSAccept() async {
    setState(() {
      _showTOSModal = false;
    });

    // Reset the global flag
    AppServiceManager().isTOSModalVisible = false;

    // Enable uploading
    final updatedConfig = _config!.copyWith(uploadEnabled: true);
    await _saveConfig(updatedConfig);

    // Make sure the UI is updated
    setState(() {
      _config = updatedConfig;
    });

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terms of Service accepted. Photo uploading has been enabled.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    // Reset the global flag
    AppServiceManager().isTOSModalVisible = false;

    // Show warning message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You must accept the Terms of Service to enable photo uploading.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildSettingsForm(),

          // TOS Modal
          if (_showTOSModal)
            TOSModal(
              onAccept: _handleTOSAccept,
              onDecline: _handleTOSDecline,
              title: 'Terms of Service',
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsForm() {
    if (_config == null) {
      return const Center(child: Text('Failed to load settings'));
    }

    final isSmallScreen = _isSmallScreen(context);
    final edgeInsets =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final sectionSpacing = isSmallScreen ? 12.0 : 16.0;

    // Calculate item count based on platform
    final int itemCount = Platform.isWindows ? 11 : 9;

    return RepaintBoundary(
      child: ListView.builder(
        controller: _scrollController,
        padding: edgeInsets,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        cacheExtent: 500,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          switch (index) {
            case 0:
              return _buildDirectoriesSection(isSmallScreen);
            case 1:
              return SizedBox(height: sectionSpacing);
            case 2:
              return _buildPhotoProcessingSection(isSmallScreen);
            case 3:
              return SizedBox(height: sectionSpacing);
            case 4:
              return _buildNotificationsSection(isSmallScreen);
            case 5:
              return SizedBox(height: sectionSpacing);
            case 6:
              return _buildSharingSection(isSmallScreen);
            case 7:
              return SizedBox(height: sectionSpacing);
            case 8:
              return Platform.isWindows
                  ? _buildWindowsSection(isSmallScreen)
                  : _buildAboutSection(isSmallScreen);
            case 9:
              return Platform.isWindows
                  ? SizedBox(height: sectionSpacing * 2)
                  : const SizedBox.shrink();
            case 10:
              return Platform.isWindows
                  ? _buildAboutSection(isSmallScreen)
                  : const SizedBox.shrink();
            default:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _buildDirectoriesSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Directories',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: spacing),
              _buildDirectoryPicker(
                label: 'Photos Directory',
                value: _config!.photosDirectory,
                isSmallScreen: isSmallScreen,
                onChanged: (value) {
                  if (value != null) {
                    final updatedConfig = _config!.copyWith(
                      photosDirectory: value,
                    );
                    _saveConfig(updatedConfig);
                  }
                },
              ),
              SizedBox(height: spacing),
              _buildDirectoryPicker(
                label: 'Logs Directory',
                value: _config!.logsDirectory,
                isSmallScreen: isSmallScreen,
                onChanged: (value) {
                  if (value != null) {
                    final updatedConfig = _config!.copyWith(
                      logsDirectory: value,
                    );
                    _saveConfig(updatedConfig);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoProcessingSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;
    final sliderWidth = isSmallScreen ? 150.0 : 200.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photo Processing',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: spacing),
              RepaintBoundary(
                child:
                    isSmallScreen
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                'Compression Delay',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: Text(
                                '${_config!.compressionDelay.toStringAsFixed(1)} seconds',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Slider(
                                value: _config!.compressionDelay,
                                min: 0.1,
                                max: 5.0,
                                divisions: 49,
                                label: _config!.compressionDelay
                                    .toStringAsFixed(1),
                                onChanged: (value) {
                                  final updatedConfig = _config!.copyWith(
                                    compressionDelay: value,
                                  );
                                  _saveConfig(updatedConfig);
                                },
                              ),
                            ),
                          ],
                        )
                        : ListTile(
                          title: const Text('Compression Delay'),
                          subtitle: Text(
                            '${_config!.compressionDelay.toStringAsFixed(1)} seconds',
                          ),
                          trailing: SizedBox(
                            width: sliderWidth,
                            child: Slider(
                              value: _config!.compressionDelay,
                              min: 0.1,
                              max: 5.0,
                              divisions: 49,
                              label: _config!.compressionDelay.toStringAsFixed(
                                1,
                              ),
                              onChanged: (value) {
                                final updatedConfig = _config!.copyWith(
                                  compressionDelay: value,
                                );
                                _saveConfig(updatedConfig);
                              },
                            ),
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;
    final sliderWidth = isSmallScreen ? 150.0 : 200.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: spacing),
              RepaintBoundary(
                child: SwitchListTile(
                  dense: isSmallScreen,
                  title: const Text('Sound Enabled'),
                  subtitle: const Text(
                    'Play a sound when a photo is processed',
                  ),
                  value: _config!.soundEnabled,
                  onChanged: (value) {
                    final updatedConfig = _config!.copyWith(
                      soundEnabled: value,
                    );
                    _saveConfig(updatedConfig);
                  },
                ),
              ),
              RepaintBoundary(
                child:
                    isSmallScreen
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                'Sound Volume',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: Text(
                                '${(_config!.soundVolume * 100).round()}%',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Slider(
                                value: _config!.soundVolume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label:
                                    '${(_config!.soundVolume * 100).round()}%',
                                onChanged:
                                    _config!.soundEnabled
                                        ? (value) {
                                          final updatedConfig = _config!
                                              .copyWith(soundVolume: value);
                                          _saveConfig(updatedConfig);
                                        }
                                        : null,
                              ),
                            ),
                          ],
                        )
                        : ListTile(
                          title: const Text('Sound Volume'),
                          subtitle: Text(
                            '${(_config!.soundVolume * 100).round()}%',
                          ),
                          trailing: SizedBox(
                            width: sliderWidth,
                            child: Slider(
                              value: _config!.soundVolume,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: '${(_config!.soundVolume * 100).round()}%',
                              onChanged:
                                  _config!.soundEnabled
                                      ? (value) {
                                        final updatedConfig = _config!.copyWith(
                                          soundVolume: value,
                                        );
                                        _saveConfig(updatedConfig);
                                      }
                                      : null,
                            ),
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharingSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sharing', style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: spacing),
              RepaintBoundary(
                child: SwitchListTile(
                  dense: isSmallScreen,
                  title: const Text('Upload Enabled'),
                  subtitle: const Text('Automatically upload processed photos'),
                  value: _config!.uploadEnabled,
                  onChanged: (value) async {
                    // If trying to enable uploads, check VRChat logging and TOS acceptance first
                    if (value) {
                      // Check VRChat logging status on Windows
                      if (Platform.isWindows) {
                        try {
                          final isLoggingEnabled = await _vrchatRegistryService.isFullLoggingEnabled();
                          if (!isLoggingEnabled) {
                            // Show warning toast about VRChat logging
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('VRChat full logging must be enabled to upload photos. Your photos cannot be processed without logging enabled.'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 5),
                                ),
                              );
                            }
                            return;
                          }
                        } catch (e) {
                          developer.log('Error checking VRChat logging status: $e', name: 'SettingsScreen');
                          // Continue with upload enabling if we can't check logging status
                        }
                      }

                      final needsToAcceptTOS = await _tosService.needsToAcceptTOS();
                      if (needsToAcceptTOS) {
                        // Check if a TOS modal is already visible
                        if (AppServiceManager().isTOSModalVisible) {
                          developer.log('TOS modal is already visible, skipping', name: 'SettingsScreen');

                          // Show a message to the user
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please accept the Terms of Service to enable uploading.'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                          return;
                        }

                        // Set the global flag
                        AppServiceManager().isTOSModalVisible = true;

                        // Show TOS modal instead of enabling uploads
                        setState(() {
                          _showTOSModal = true;
                        });
                        return;
                      }
                    }

                    // If disabling uploads or all checks passed, proceed normally
                    final updatedConfig = _config!.copyWith(
                      uploadEnabled: value,
                    );
                    _saveConfig(updatedConfig);
                  },
                ),
              ),
              RepaintBoundary(
                child: SwitchListTile(
                  dense: isSmallScreen,
                  title: const Text('Auto-Copy Gallery URL'),
                  subtitle: const Text('Automatically copy gallery URL to clipboard after upload'),
                  value: _config!.autoCopyGalleryUrl,
                  onChanged: _config!.uploadEnabled ? (value) {
                    final updatedConfig = _config!.copyWith(
                      autoCopyGalleryUrl: value,
                    );
                    _saveConfig(updatedConfig);
                  } : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: spacing),

              // Version and update status in a single component
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _updateAvailable
                    ? Theme.of(context).colorScheme.errorContainer.withAlpha(50)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left side - App info
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _updateAvailable ? Icons.system_update : Icons.info_outline,
                            color: _updateAvailable
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'GalleVR',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                RichText(
                                  text: TextSpan(
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    children: [
                                      TextSpan(
                                        text: 'Version $_appVersion',
                                      ),
                                      if (_updateAvailable && _latestVersion != null) ...[
                                        const TextSpan(
                                          text: ' • ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'Update: $_latestVersion',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.error,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right side - Buttons
                    if (_updateAvailable && _latestVersion != null) ...[
                      TextButton(
                        onPressed: () async {
                          await _checkForUpdatesWithFeedback();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Check Again'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton.icon(
                        onPressed: () {
                          _updateService.openReleasesPage();
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ] else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Check for Updates'),
                        onPressed: () async {
                          await _checkForUpdatesWithFeedback();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Platform information
              ListTile(
                dense: isSmallScreen,
                title: const Text('Platform'),
                subtitle: Text(_getPlatformName()),
                leading: const Icon(Icons.devices),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryPicker({
    required String label,
    required String value,
    required Function(String?) onChanged,
    bool isSmallScreen = false,
  }) {
    final verticalLayout = isSmallScreen;
    final spacing = isSmallScreen ? 6.0 : 8.0;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          SizedBox(height: spacing),
          if (verticalLayout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    value.isEmpty ? 'Not set' : value,
                    style: TextStyle(
                      color: value.isEmpty ? Colors.grey : null,
                      fontSize: isSmallScreen ? 13 : 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: spacing),
                ElevatedButton(
                  onPressed: () => _pickDirectory(onChanged),
                  child: const Text('Browse'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      value.isEmpty ? 'Not set' : value,
                      style: TextStyle(
                        color: value.isEmpty ? Colors.grey : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _pickDirectory(onChanged),
                  child: const Text('Browse'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pickDirectory(Function(String?) onChanged) async {
    try {
      if (Platform.isAndroid) {
        final permissionService = PermissionService();
        final hasPermission = await permissionService.checkStoragePermissions();

        if (!hasPermission) {
          if (mounted) {
            final shouldRequest =
                await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Storage Permission Required'),
                        content: const Text(
                          'GalleVR needs storage access to select directories. Please grant the permission.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Grant Permission'),
                          ),
                        ],
                      ),
                ) ??
                false;

            if (shouldRequest) {
              if (mounted) {
                final granted = await permissionService
                    .requestStoragePermissions(context);
                if (!granted) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Storage permission is required to select a directory',
                        ),
                      ),
                    );
                  }
                  return;
                }
              } else {
                return;
              }
            } else {
              return;
            }
          } else {
            return;
          }
        }
      }

      developer.log('Opening directory picker...', name: 'SettingsScreen');
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        developer.log(
          'Directory selected: $selectedDirectory',
          name: 'SettingsScreen',
        );

        final directory = Directory(selectedDirectory);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        if (Platform.isAndroid) {
          final segments = path.split(selectedDirectory);

          developer.log('Path segments: $segments', name: 'SettingsScreen');

          int patternCount = 0;
          for (int i = 0; i < segments.length - 1; i++) {
            if (i + 1 < segments.length &&
                segments[i] == 'Pictures' &&
                segments[i + 1] == 'VRChat') {
              patternCount++;
            }
          }

          if (patternCount > 1) {
            developer.log(
              'Detected duplicated path pattern: $selectedDirectory',
              name: 'SettingsScreen',
            );

            int firstPicturesIndex = -1;
            for (int i = 0; i < segments.length - 1; i++) {
              if (segments[i] == 'Pictures' && segments[i + 1] == 'VRChat') {
                firstPicturesIndex = i;
                break;
              }
            }

            if (firstPicturesIndex >= 0) {
              final correctedSegments = segments.sublist(
                0,
                firstPicturesIndex + 2,
              );
              final correctedPath = path.joinAll(correctedSegments);

              developer.log(
                'Corrected path: $correctedPath',
                name: 'SettingsScreen',
              );
              selectedDirectory = correctedPath;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fixed duplicated path segments'),
                  ),
                );
              }
            }
          }

          patternCount = 0;
          for (int i = 0; i < segments.length - 1; i++) {
            if (i + 1 < segments.length &&
                segments[i] == 'Documents' &&
                segments[i + 1] == 'Logs') {
              patternCount++;
            }
          }

          if (patternCount > 1) {
            developer.log(
              'Detected duplicated logs path pattern: $selectedDirectory',
              name: 'SettingsScreen',
            );

            int firstDocsIndex = -1;
            for (int i = 0; i < segments.length - 1; i++) {
              if (segments[i] == 'Documents' && segments[i + 1] == 'Logs') {
                firstDocsIndex = i;
                break;
              }
            }

            if (firstDocsIndex >= 0) {
              final correctedSegments = segments.sublist(0, firstDocsIndex + 2);
              final correctedPath = path.joinAll(correctedSegments);

              developer.log(
                'Corrected logs path: $correctedPath',
                name: 'SettingsScreen',
              );
              selectedDirectory = correctedPath;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fixed duplicated path segments'),
                  ),
                );
              }
            }
          }
        }

        onChanged(selectedDirectory);
      } else {
        developer.log('Directory selection cancelled', name: 'SettingsScreen');
      }
    } catch (e) {
      developer.log(
        'Error picking directory: $e',
        name: 'SettingsScreen',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking directory: $e')));
      }
    }
  }

  String _getPlatformName() {
    final platformType = _platformService.getPlatformType();
    switch (platformType) {
      case PlatformType.windows:
        return 'Windows';
      case PlatformType.android:
        return 'Android';
      default:
        return 'Unknown';
    }
  }

  Widget _buildWindowsSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Windows Settings', style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: spacing),
              RepaintBoundary(
                child: SwitchListTile(
                  dense: isSmallScreen,
                  title: const Text('Minimize to System Tray'),
                  subtitle: const Text(
                    'Keep the app running in the system tray when closed',
                  ),
                  value: _config!.minimizeToTray,
                  onChanged: (value) {
                    final updatedConfig = _config!.copyWith(
                      minimizeToTray: value,
                    );
                    _saveConfig(updatedConfig);
                  },
                ),
              ),
              RepaintBoundary(
                child: SwitchListTile(
                  dense: isSmallScreen,
                  title: const Text('Start with Windows'),
                  subtitle: const Text(
                    'Automatically start GalleVR when Windows starts',
                  ),
                  value: _config!.startWithWindows,
                  onChanged: (value) {
                    final updatedConfig = _config!.copyWith(
                      startWithWindows: value,
                    );
                    _saveConfig(updatedConfig);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
