import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
import '../widgets/app_switch.dart';
import '../widgets/tinted_button.dart';
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
  AuthData? _authDataSec;
  String _appVersion = '1.0.0';
  bool _updateAvailable = false;
  String? _latestVersion;
  bool _showTOSModal = false;

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

    AppServiceManager().configStream.listen((updatedConfig) {
      if (mounted) {
        setState(() {
          _config = updatedConfig;
        });
      }
    });

    _authSubscription = AppServiceManager().authDataStream.listen((
      updatedAuth,
    ) async {
      final authDataSec = await _vrchatService.loadAuthDataSecondary();
      if (mounted) {
        setState(() {
          _authData = updatedAuth;
          _authDataSec = authDataSec;
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

  Future<void> _checkForUpdatesWithFeedback() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking for updates...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    await _checkForUpdates();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              _updateAvailable
                  ? Text(
                    'Update available! Version $_latestVersion is ready to download.',
                  )
                  : const Text('You have the latest version.'),
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
    try {
      developer.log('Loading config...', name: 'SettingsScreen');
      final config = await _configRepository.loadConfig();
      developer.log('Config loaded successfully', name: 'SettingsScreen');

      final authData = await _vrchatService.loadAuthData();
      final authDataSec = await _vrchatService.loadAuthDataSecondary();

      setState(() {
        _config = config;
        _authData = authData;
        _authDataSec = authDataSec;
      });
    } catch (e) {
      developer.log(
        'Error loading config: $e',
        name: 'SettingsScreen',
        error: e,
      );
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

    AppServiceManager().isTOSModalVisible = false;

    final updatedConfig = _config!.copyWith(uploadEnabled: true);
    await _saveConfig(updatedConfig);

    setState(() {
      _config = updatedConfig;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Terms of Service accepted. Photo uploading has been enabled.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    AppServiceManager().isTOSModalVisible = false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You must accept the Terms of Service to enable photo uploading.',
        ),
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
    final sectionSpacing = isSmallScreen ? 16.0 : 24.0;

    final int itemCount = Platform.isWindows ? 12 : 10;

    return Theme(
      data: Theme.of(context).copyWith(
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPad =
              isSmallScreen
                  ? 16.0
                  : max(28.0, (constraints.maxWidth - 1200) / 2);
          final edgeInsets = EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: isSmallScreen ? 16 : 24,
          );
          return RepaintBoundary(
            child: ListView.builder(
              scrollCacheExtent: const ScrollCacheExtent.pixels(500.0),
              controller: _scrollController,
              padding: edgeInsets,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
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
      );
        },
      ),
    );
  }

  Widget _buildCardHeader(IconData icon, Color iconColor, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.textColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.edit_note_rounded,
              AppTheme.brandPurple,
              'Editor Tools',
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_upload_rounded,
                    color: AppTheme.brandPurple,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Mass Upload Screenshots',
                      style: TextStyle(
                        color: AppTheme.bodyTextColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TintedButton.neutral(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const MassUploadScreen(),
                        ),
                      );
                    },
                    label: 'Open',
                    appendIcon: Icons.chevron_right_rounded,
                    dense: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoriesSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    final hasVRC =
        (_authData != null && !_authData!.userId.startsWith('U-')) ||
        (_authDataSec != null && !_authDataSec!.userId.startsWith('U-'));
    final hasResonite =
        (_authData != null && _authData!.userId.startsWith('U-')) ||
        (_authDataSec != null && _authDataSec!.userId.startsWith('U-'));
    final showVRC = hasVRC || (!hasVRC && !hasResonite);
    final showResonite = hasResonite;

    final widgets = <Widget>[];

    if (showVRC) {
      widgets.add(
        _buildDirectoryPicker(
          label: 'VRChat Photos Directory',
          value: _config!.photosDirectory,
          isSmallScreen: isSmallScreen,
          onChanged: (value) {
            if (value != null) {
              _saveConfig(_config!.copyWith(photosDirectory: value));
            }
          },
        ),
      );
      widgets.add(
        _buildDirectoryPicker(
          label: 'VRChat Logs Directory',
          value: _config!.logsDirectory,
          isSmallScreen: isSmallScreen,
          onChanged: (value) {
            if (value != null) {
              _saveConfig(_config!.copyWith(logsDirectory: value));
            }
          },
        ),
      );
    }

    if (showResonite) {
      widgets.add(
        _buildDirectoryPicker(
          label: 'Resonite Photos Directory',
          value: _config!.resonitePhotosDirectory,
          isSmallScreen: isSmallScreen,
          onChanged: (value) {
            if (value != null) {
              _saveConfig(_config!.copyWith(resonitePhotosDirectory: value));
            }
          },
        ),
      );
    }

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.folder_copy_rounded,
              AppTheme.iconWorld,
              'Directories',
            ),
            ...widgets,
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoProcessingSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.auto_fix_high_rounded,
              AppTheme.iconPhotos,
              'Processing',
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  const Tooltip(
                    message: 'Wait time before compressing a newly saved photo',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: AppTheme.iconPhotos,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Compression Delay',
                          style: TextStyle(
                            color: AppTheme.bodyTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Slider(
                      value: _config!.compressionDelay,
                      min: 0.1,
                      max: 5.0,
                      divisions: 49,
                      onChanged: (value) {
                        _saveConfig(_config!.copyWith(compressionDelay: value));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_config!.compressionDelay.toStringAsFixed(1)}s',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
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
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.notifications_active_rounded,
              AppTheme.iconWorld,
              'Notifications',
            ),
            _buildCustomSwitchRow(
              icon: Icons.volume_up_rounded,
              iconColor: AppTheme.iconWorld,
              title: 'Sound Alerts',
              value: _config!.soundEnabled,
              onChanged:
                  (value) =>
                      _saveConfig(_config!.copyWith(soundEnabled: value)),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: AppTheme.brandPurple,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'Volume',
                      style: TextStyle(
                        color: AppTheme.bodyTextColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _config!.soundVolume,
                      onChanged:
                          _config!.soundEnabled
                              ? (v) =>
                                  _saveConfig(_config!.copyWith(soundVolume: v))
                              : null,
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
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.share_rounded,
              AppTheme.iconPlayers,
              'Sharing',
            ),
            _buildCustomSwitchRow(
              icon: Icons.cloud_upload_outlined,
              iconColor: AppTheme.iconPlayers,
              title: 'Automatic Uploading',
              value: _config!.uploadEnabled,
              onChanged: (value) async {
                if (value) {
                  final hasVRC =
                      (_authData != null &&
                          !_authData!.userId.startsWith('U-')) ||
                      (_authDataSec != null &&
                          !_authDataSec!.userId.startsWith('U-'));
                  if (hasVRC && Platform.isWindows) {
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
              icon: Icons.link_rounded,
              iconColor: AppTheme.iconFeed,
              title: 'Auto-Copy URL',
              tooltip: 'Copy gallery link after upload',
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
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.info_outline_rounded,
              AppTheme.brandPurple,
              'About',
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorderColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(
                    _updateAvailable
                        ? Icons.system_update_rounded
                        : Icons.update_rounded,
                    color:
                        _updateAvailable
                            ? AppTheme.warningColor
                            : AppTheme.brandPurple,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: AppTheme.bodyTextColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(text: 'Version $_appVersion'),
                          if (_updateAvailable && _latestVersion != null) ...[
                            const TextSpan(
                              text: '  •  ',
                              style: TextStyle(
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                            TextSpan(
                              text: 'Update $_latestVersion available',
                              style: const TextStyle(
                                color: AppTheme.warningColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_updateAvailable && _latestVersion != null) ...[
                    TintedButton.neutral(
                      onPressed: _checkForUpdatesWithFeedback,
                      label: 'Check Again',
                      dense: true,
                    ),
                    const SizedBox(width: 8),
                    TintedButton(
                      onPressed: _updateService.openReleasesPage,
                      icon: Icons.download_rounded,
                      label: 'Download',
                      color: AppTheme.brandPurple,
                      dense: true,
                    ),
                  ] else
                    TintedButton.neutral(
                      onPressed: _checkForUpdatesWithFeedback,
                      icon: Icons.refresh_rounded,
                      label: 'Check for Updates',
                      dense: true,
                    ),
                ],
              ),
            ),
            _buildCustomInfoRow(
              title: 'Platform',
              subtitle: _getPlatformName(),
              leading: Icons.devices_rounded,
            ),
            if (Platform.isWindows || Platform.isLinux)
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.cardBorderColor),
                  ),
                ),
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.power_settings_new_rounded,
                          color: AppTheme.errorTextColor,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Exit Application',
                          style: TextStyle(
                            color: AppTheme.bodyTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    TintedButton(
                      onPressed:
                          () => AppServiceManager().handleWindowClose(
                            forceExit: true,
                          ),
                      icon: Icons.power_settings_new_rounded,
                      label: 'Quit GalleVR',
                      color: AppTheme.errorColor,
                      dense: true,
                    ),
                  ],
                ),
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
    final pathBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBase,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.buttonBorderColor),
      ),
      child: Text(
        value.isEmpty ? 'Not set' : value,
        style: TextStyle(
          color:
              value.isEmpty
                  ? AppTheme.secondaryTextColor.withValues(alpha: 0.6)
                  : AppTheme.bodyTextColor,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.bodyTextColor,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          if (isSmallScreen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                pathBox,
                const SizedBox(height: 8),
                TintedButton.neutral(
                  onPressed: () => _pickDirectory(onChanged),
                  icon: Icons.folder_open_rounded,
                  label: 'Browse',
                  dense: true,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: pathBox),
                const SizedBox(width: 12),
                TintedButton.neutral(
                  onPressed: () => _pickDirectory(onChanged),
                  icon: Icons.folder_open_rounded,
                  label: 'Browse',
                  dense: true,
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
      case PlatformType.linux:
        return 'Linux';
      default:
        return 'Unknown';
    }
  }

  Widget _buildWindowsSection([bool isSmallScreen = false]) {
    final padding =
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

    return RepaintBoundary(
      child: AppCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHeader(
              Icons.settings_applications_rounded,
              AppTheme.iconWorld,
              'Windows Settings',
            ),
            RepaintBoundary(
              child: _buildCustomSwitchRow(
                icon: Icons.minimize_rounded,
                iconColor: AppTheme.iconWorld,
                title: 'Minimize to System Tray',
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
                icon: Icons.power_rounded,
                iconColor: AppTheme.iconPlayers,
                title: 'Start with Windows',
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
                icon: Icons.system_update_alt_rounded,
                iconColor: AppTheme.brandPurple,
                title: 'Auto Updates',
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
    String? tooltip,
    required bool value,
    required ValueChanged<bool>? onChanged,
    IconData? icon,
    Color? iconColor,
  }) {
    final enabled = onChanged != null;
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor ?? AppTheme.brandPurple, size: 18),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.bodyTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onTap: enabled ? () => onChanged(!value) : null,
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child:
                        tooltip != null
                            ? Tooltip(message: tooltip, child: labelRow)
                            : labelRow,
                  ),
                  const SizedBox(width: 16),
                  AppSwitch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomInfoRow({
    required String title,
    required String subtitle,
    required IconData leading,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(leading, color: AppTheme.secondaryTextColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.bodyTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.secondaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
