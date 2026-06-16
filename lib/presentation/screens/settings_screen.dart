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
import '../../data/services/vrchat_service.dart';
import '../../data/models/verification_models.dart';
import '../widgets/tos_modal.dart';
import '../widgets/app_card.dart';
import '../theme/app_theme.dart';
import 'mass_upload_screen.dart';

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
  final VRChatService _vrchatService = VRChatService();

  ConfigModel? _config;
  AuthData? _authData;
  bool _isLoading = true;
  String _appVersion = '1.0.0'; // Default version
  bool _updateAvailable = false;
  String? _latestVersion;
  bool _showTOSModal = false;

  // Stream subscription for update status
  late StreamSubscription<bool>? _updateSubscription;
  StreamSubscription<AuthData?>? _authSubscription;

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadAppVersion();

    // Listen for update status changes
    _updateSubscription = _updateService.updateAvailableStream.listen((
      hasUpdate,
    ) {
      if (mounted) {
        setState(() {
          _updateAvailable = hasUpdate;
          _latestVersion = _updateService.latestVersion;
        });
      }
    });

    // Listen for config changes from other parts of the app
    AppServiceManager().configStream.listen((updatedConfig) {
      if (mounted) {
        setState(() {
          _config = updatedConfig;
        });
      }
    });

    // Listen for auth changes from other parts of the app
    _authSubscription = AppServiceManager().authDataStream.listen((
      updatedAuth,
    ) {
      if (mounted) {
        setState(() {
          _authData = updatedAuth;
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
      developer.log(
        'Update check completed. Update available: $_updateAvailable, Latest version: $_latestVersion',
        name: 'SettingsScreen',
      );
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
          content:
              _updateAvailable
                  ? Text(
                    'Update available! Version $_latestVersion is ready to download.',
                  )
                  : const Text('You have the latest version.'),
          backgroundColor:
              _updateAvailable
                  ? Theme.of(context).colorScheme.primary
                  : Colors.green,
          duration: const Duration(seconds: 3),
          action:
              _updateAvailable
                  ? SnackBarAction(
                    label: 'DOWNLOAD',
                    textColor: Colors.white,
                    onPressed: () {
                      _updateService.openReleasesPage();
                    },
                  )
                  : null,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _updateSubscription?.cancel();
    _authSubscription?.cancel();
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

      final authData = await _vrchatService.loadAuthData();

      setState(() {
        _config = config;
        _authData = authData;
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
          content: Text(
            'Terms of Service accepted. Photo uploading has been enabled.',
          ),
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
        content: Text(
          'You must accept the Terms of Service to enable photo uploading.',
        ),
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
          _buildSettingsForm(),

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
    final int itemCount = Platform.isWindows ? 12 : 10;

    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      child: RepaintBoundary(
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
                return _authData?.isEditor == true
                    ? Padding(
                      padding: EdgeInsets.only(top: sectionSpacing),
                      child: _buildEditorSection(isSmallScreen),
                    )
                    : const SizedBox.shrink();
              case 4:
                return SizedBox(height: sectionSpacing);
              case 5:
                return _buildNotificationsSection(isSmallScreen);
              case 6:
                return SizedBox(height: sectionSpacing);
              case 7:
                return _buildSharingSection(isSmallScreen);
              case 8:
                return SizedBox(height: sectionSpacing);
              case 9:
                return Platform.isWindows
                    ? _buildWindowsSection(isSmallScreen)
                    : _buildAboutSection(isSmallScreen);
              case 10:
                return Platform.isWindows
                    ? SizedBox(height: sectionSpacing)
                    : const SizedBox.shrink();
              case 11:
                return Platform.isWindows
                    ? _buildAboutSection(isSmallScreen)
                    : const SizedBox.shrink();
              default:
                return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }

  Widget _buildEditorSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(20);

    return RepaintBoundary(
      child: AppCard(
        color: const Color(0xFF8b5cf6).withOpacity(0.1),
        borderColor: const Color(0xFF8b5cf6).withOpacity(0.2),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFFa78bfa),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Editor Tools',
                  style: TextStyle(
                    color: Color(0xFFa78bfa),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const MassUploadScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8b5cf6).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_upload_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mass Upload Screenshots',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Upload edited photos in bulk',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoriesSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(20);
    final spacing = isSmallScreen ? 16.0 : 20.0;
    final isResonite = _authData?.userId.startsWith('U-') == true;

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.folder_copy_rounded,
                  color: Color(0xFF60a5fa),
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Directories',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            if (isResonite)
              _buildDirectoryPicker(
                label: 'Resonite Photos Directory',
                value: _config!.resonitePhotosDirectory,
                isSmallScreen: isSmallScreen,
                onChanged: (value) {
                  if (value != null) {
                    _saveConfig(
                      _config!.copyWith(resonitePhotosDirectory: value),
                    );
                  }
                },
              )
            else ...[
              _buildDirectoryPicker(
                label: 'Photos Directory',
                value: _config!.photosDirectory,
                isSmallScreen: isSmallScreen,
                onChanged: (value) {
                  if (value != null) {
                    _saveConfig(_config!.copyWith(photosDirectory: value));
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
                    _saveConfig(_config!.copyWith(logsDirectory: value));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoProcessingSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(20);
    final accentColor = const Color(0xFFf472b6);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, color: accentColor, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Processing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compression Delay',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_config!.compressionDelay.toStringAsFixed(1)} seconds',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: accentColor,
                        inactiveTrackColor: accentColor.withOpacity(0.2),
                        thumbColor: accentColor,
                        overlayColor: accentColor.withOpacity(0.1),
                      ),
                      child: Slider(
                        value: _config!.compressionDelay,
                        min: 0.1,
                        max: 5.0,
                        divisions: 49,
                        onChanged: (value) {
                          _saveConfig(
                            _config!.copyWith(compressionDelay: value),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(20);
    final accentColor = const Color(0xFF60a5fa);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: accentColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCustomSwitchRow(
              title: 'Sound Alerts',
              subtitle: 'Play sound when photo is processed',
              activeColor: accentColor,
              value: _config!.soundEnabled,
              onChanged:
                  (value) =>
                      _saveConfig(_config!.copyWith(soundEnabled: value)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'Volume',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: accentColor,
                        inactiveTrackColor: accentColor.withOpacity(0.2),
                        thumbColor: accentColor,
                      ),
                      child: Slider(
                        value: _config!.soundVolume,
                        onChanged:
                            _config!.soundEnabled
                                ? (v) => _saveConfig(
                                  _config!.copyWith(soundVolume: v),
                                )
                                : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharingSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(20);
    final accentColor = const Color(0xFF4ade80);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_rounded, color: accentColor, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Sharing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCustomSwitchRow(
              title: 'Automatic Uploading',
              subtitle: 'Upload processed photos automatically',
              activeColor: accentColor,
              value: _config!.uploadEnabled,
              onChanged: (value) async {
                if (value) {
                  final isResonite = _authData?.userId.startsWith('U-') == true;
                  if (!isResonite && Platform.isWindows) {
                    try {
                      final isLoggingEnabled =
                          await _vrchatRegistryService.isFullLoggingEnabled();
                      if (!isLoggingEnabled) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'VRChat full logging must be enabled to upload photos.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }
                    } catch (e) {
                      developer.log(
                        'Error checking logging: $e',
                        name: 'SettingsScreen',
                      );
                    }
                  }

                  final needsToAcceptTOS = await _tosService.needsToAcceptTOS();
                  if (needsToAcceptTOS) {
                    if (AppServiceManager().isTOSModalVisible) return;
                    AppServiceManager().isTOSModalVisible = true;
                    setState(() => _showTOSModal = true);
                    return;
                  }
                }
                _saveConfig(_config!.copyWith(uploadEnabled: value));
              },
            ),
            _buildCustomSwitchRow(
              title: 'Auto-Copy URL',
              subtitle: 'Copy gallery link after upload',
              activeColor: accentColor,
              value: _config!.autoCopyGalleryUrl,
              onChanged:
                  _config!.uploadEnabled
                      ? (v) =>
                          _saveConfig(_config!.copyWith(autoCopyGalleryUrl: v))
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFa78bfa),
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'About',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),

            // Version and update status in a single component
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color:
                    _updateAvailable
                        ? Colors.amber.withOpacity(0.1)
                        : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      _updateAvailable
                          ? Colors.amber.withOpacity(0.3)
                          : Colors.white.withOpacity(0.08),
                ),
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
                          _updateAvailable
                              ? Icons.system_update
                              : Icons.info_outline,
                          color:
                              _updateAvailable
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
                                    TextSpan(text: 'Version $_appVersion'),
                                    if (_updateAvailable &&
                                        _latestVersion != null) ...[
                                      const TextSpan(
                                        text: ' • ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Update: $_latestVersion',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.error,
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
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
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
            _buildCustomInfoRow(
              dense: isSmallScreen,
              title: 'Platform',
              subtitle: _getPlatformName(),
              leading: Icons.devices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryPicker({
    required String label,
    required String value,
    required bool isSmallScreen,
    required Function(String?) onChanged,
  }) {
    final double spacing = isSmallScreen ? 8 : 16;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (isSmallScreen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    value.isEmpty ? 'Not set' : value,
                    style: TextStyle(
                      color: value.isEmpty ? Colors.white24 : Colors.white70,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                _buildModernButton(
                  onPressed: () => _pickDirectory(onChanged),
                  label: 'Browse',
                  color: AppTheme.primaryColor,
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
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      value.isEmpty ? 'Not set' : value,
                      style: TextStyle(
                        color: value.isEmpty ? Colors.white24 : Colors.white70,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildModernButton(
                  onPressed: () => _pickDirectory(onChanged),
                  label: 'Browse',
                  color: AppTheme.primaryColor,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildModernButton({
    required VoidCallback? onPressed,
    required String label,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: (onPressed == null ? Colors.white10 : color).withOpacity(
              0.1,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (onPressed == null ? Colors.white10 : color).withOpacity(
                0.2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: onPressed == null ? Colors.white24 : color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
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
      case PlatformType.linux:
        return 'Linux';
      default:
        return 'Unknown';
    }
  }

  Widget _buildWindowsSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16);
    final spacing = isSmallScreen ? 12.0 : 16.0;

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.settings_applications_rounded,
                  color: Color(0xFF60a5fa),
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Windows Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            RepaintBoundary(
              child: _buildCustomSwitchRow(
                dense: isSmallScreen,
                title: 'Minimize to System Tray',
                subtitle: 'Keep the app running in the system tray when closed',
                activeColor: Theme.of(context).colorScheme.primary,
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
              child: _buildCustomSwitchRow(
                dense: isSmallScreen,
                title: 'Start with Windows',
                subtitle: 'Automatically start GalleVR when Windows starts',
                activeColor: Theme.of(context).colorScheme.primary,
                value: _config!.startWithWindows,
                onChanged: (value) {
                  final updatedConfig = _config!.copyWith(
                    startWithWindows: value,
                  );
                  _saveConfig(updatedConfig);
                },
              ),
            ),
            RepaintBoundary(
              child: _buildCustomSwitchRow(
                dense: isSmallScreen,
                title: 'Auto Updates',
                subtitle:
                    'Automatically download and install updates in the background',
                activeColor: Theme.of(context).colorScheme.primary,
                value: _config!.autoUpdateEnabled,
                onChanged: (value) {
                  final updatedConfig = _config!.copyWith(
                    autoUpdateEnabled: value,
                  );
                  _saveConfig(updatedConfig);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required Color activeColor,
    bool dense = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged != null ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: dense ? 8 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: activeColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomInfoRow({
    required String title,
    required String subtitle,
    required IconData leading,
    bool dense = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: dense ? 8 : 12,
          ),
          child: Row(
            children: [
              Icon(leading, color: Colors.white54, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
