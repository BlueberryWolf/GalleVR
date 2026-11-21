import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/app_switch.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/vrchat_registry_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/vrchat_service.dart';
import 'home_screen.dart';
import 'verification_screen.dart';
import '../widgets/app_card.dart';
import '../widgets/tinted_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  final AppServiceManager _appServiceManager = AppServiceManager();
  final VRChatService _vrchatService = VRChatService();
  final VRChatRegistryService _vrchatRegistryService = VRChatRegistryService();
  final _platformService = PlatformServiceFactory.getPlatformService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  bool _isLoading = false;
  bool _permissionsGranted = false;
  bool _isVRChatLoggingEnabled = false;
  bool _isEnablingLogging = false;
  bool _isVRChatRunning = false;
  bool _justEnabledLogging = false;

  bool _isLogsDirectoryAvailable = false;
  bool _isCheckingLogsDirectory = false;

  bool _wantsToLinkAccount = true;
  String? _selectedPlatform;

  bool _minimizeToTray = true;
  bool _startWithWindows = true;

  int _currentStep = 0;

  final PageController _pageController = PageController();

  static const Color _brandPurple = AppTheme.brandPurple;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );

    _animationController.forward();

    if (Platform.isAndroid) {
      _checkPermissions();
    } else {
      setState(() {
        _permissionsGranted = true;
      });
    }

    _initializeVRChatService();

    if (Platform.isWindows) {
      _checkVRChatLoggingStatus();
    } else {
      _checkLogsDirectoryAvailability();
    }

    _loadCurrentStep();
  }

  Future<void> _checkVRChatLoggingStatus() async {
    developer.log('Checking VRChat logging status', name: 'OnboardingScreen');

    try {
      final isEnabled = await _vrchatRegistryService.isFullLoggingEnabled();

      developer.log(
        'VRChat logging status: $isEnabled',
        name: 'OnboardingScreen',
      );

      if (mounted) {
        setState(() {
          _isVRChatLoggingEnabled = isEnabled;
        });
      }
    } catch (e) {
      developer.log(
        'Error checking VRChat logging status: $e',
        name: 'OnboardingScreen',
      );
    }
  }

  Future<void> _checkLogsDirectoryAvailability() async {
    if (Platform.isWindows) return;

    developer.log(
      'Checking VRChat logs directory and file content',
      name: 'OnboardingScreen',
    );

    setState(() {
      _isCheckingLogsDirectory = true;
    });

    try {
      final logsDirectory = await _platformService.getLogsDirectory();

      developer.log(
        'Logs directory path: $logsDirectory',
        name: 'OnboardingScreen',
      );

      bool hasValidLogs = false;

      if (logsDirectory.isNotEmpty) {
        final logsDir = Directory(logsDirectory);
        final exists = await logsDir.exists();

        developer.log(
          'Logs directory exists: $exists',
          name: 'OnboardingScreen',
        );

        if (exists) {
          hasValidLogs = await _checkForValidLogFiles(logsDir);
        }
      }

      if (mounted) {
        setState(() {
          _isLogsDirectoryAvailable = hasValidLogs;
          _isCheckingLogsDirectory = false;
        });
      }
    } catch (e) {
      developer.log(
        'Error checking logs directory availability: $e',
        name: 'OnboardingScreen',
      );

      if (mounted) {
        setState(() {
          _isLogsDirectoryAvailable = false;
          _isCheckingLogsDirectory = false;
        });
      }
    }
  }

  Future<bool> _checkForValidLogFiles(Directory logsDir) async {
    try {
      developer.log(
        'Checking for valid log files in: ${logsDir.path}',
        name: 'OnboardingScreen',
      );

      const logPattern = 'output_log_';
      bool foundValidLog = false;
      int totalLogFiles = 0;
      int emptyLogFiles = 0;

      await for (final entity in logsDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;

          if (fileName.startsWith(logPattern) && fileName.endsWith('.txt')) {
            totalLogFiles++;

            try {
              final fileSize = await entity.length();
              developer.log(
                'Found log file: $fileName, size: $fileSize bytes',
                name: 'OnboardingScreen',
              );

              if (fileSize > 0) {
                final isRecent = await _isLogFileRecent(entity);
                if (isRecent) {
                  foundValidLog = true;
                  developer.log(
                    'Valid log file found: $fileName (size: $fileSize bytes)',
                    name: 'OnboardingScreen',
                  );
                  break;
                }
              } else {
                emptyLogFiles++;
                developer.log(
                  'Empty log file found: $fileName',
                  name: 'OnboardingScreen',
                );
              }
            } catch (e) {
              developer.log(
                'Error checking log file $fileName: $e',
                name: 'OnboardingScreen',
              );
            }
          }
        }
      }

      developer.log(
        'Log file summary - Total: $totalLogFiles, Empty: $emptyLogFiles, Valid: $foundValidLog',
        name: 'OnboardingScreen',
      );

      return foundValidLog;
    } catch (e) {
      developer.log(
        'Error checking for valid log files: $e',
        name: 'OnboardingScreen',
      );
      return false;
    }
  }

  Future<bool> _isLogFileRecent(File logFile) async {
    try {
      final now = DateTime.now();
      final fileModified = await logFile.lastModified();
      final isRecent = now.difference(fileModified).inDays < 7;

      developer.log(
        'Log file recency check - Recent: $isRecent, Modified: $fileModified',
        name: 'OnboardingScreen',
      );

      return isRecent;
    } catch (e) {
      developer.log(
        'Error checking log file recency: $e',
        name: 'OnboardingScreen',
      );
      return false;
    }
  }

  Future<void> _enableVRChatLogging() async {
    if (_isEnablingLogging) return;

    developer.log(
      'Enabling VRChat logging from onboarding screen',
      name: 'OnboardingScreen',
    );

    setState(() {
      _isEnablingLogging = true;
    });

    try {
      final success = await _vrchatRegistryService.enableFullLogging();

      developer.log(
        'VRChat logging enable result: $success',
        name: 'OnboardingScreen',
      );

      final isRunning = await _vrchatRegistryService.isVRChatRunning();

      developer.log(
        'VRChat running status: $isRunning',
        name: 'OnboardingScreen',
      );

      if (mounted) {
        setState(() {
          _isVRChatLoggingEnabled = success;
          _isEnablingLogging = false;
          _isVRChatRunning = isRunning;
          _justEnabledLogging = success;
        });
      }
    } catch (e) {
      developer.log(
        'Error enabling VRChat logging: $e',
        name: 'OnboardingScreen',
      );

      if (mounted) {
        setState(() {
          _isEnablingLogging = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initializeVRChatService() async {
    try {
      await _vrchatService.initialize();
    } catch (e) {
      developer.log(
        'Error initializing VRChat service: $e',
        name: 'OnboardingScreen',
      );
    }
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      final hasPermissions = await _permissionService.checkStoragePermissions();
      if (mounted) {
        setState(() {
          _permissionsGranted = hasPermissions;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _permissionsGranted = true;
        });
      }
    }
  }

  Future<void> _loadCurrentStep() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStep = prefs.getInt('onboarding_step') ?? 0;
      final savedPlatform = prefs.getString('onboarding_platform');
      if (mounted) {
        setState(() {
          _selectedPlatform = savedPlatform;
          if (savedStep > 0) {
            _currentStep = savedStep;
          }
        });
        if (savedStep > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(savedStep);
            }
          });
        }
      }
    } catch (e) {
      developer.log(
        'Error loading saved onboarding step: $e',
        name: 'OnboardingScreen',
      );
    }
  }

  Future<void> _saveCurrentStep(int step) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('onboarding_step', step);
    } catch (e) {
      developer.log(
        'Error saving onboarding step: $e',
        name: 'OnboardingScreen',
      );
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      setState(() {
        _isLoading = true;
      });

      final granted = await _permissionService.requestStoragePermissions(
        context,
      );

      if (mounted) {
        setState(() {
          _permissionsGranted = granted;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _permissionsGranted = true;
        });
      }
    }
  }

  void _nextStep() {
    final steps = _getSteps();
    final maxStep = steps.length - 1;
    if (_currentStep < maxStep) {
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _proceedToWebConnection() async {
    setState(() {
      _wantsToLinkAccount = true;
    });
    _nextStep();
  }

  Future<void> _finishOnboarding() async {
    if (Platform.isWindows) {
      await _saveWindowsSettings();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('onboarding_step');
    } catch (_) {}

    await _appServiceManager.markOnboardingComplete();

    if (mounted) {
      if (_wantsToLinkAccount) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) =>
                    VerificationScreen(initialPlatform: _selectedPlatform),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialTabIndex: 0),
          ),
        );
      }
    }
  }

  Future<void> _proceedToLocalOnly() async {
    setState(() {
      _wantsToLinkAccount = false;
    });
    _nextStep();
  }

  Future<void> _saveWindowsSettings() async {
    try {
      final currentConfig = _appServiceManager.config;
      if (currentConfig != null) {
        final updatedConfig = currentConfig.copyWith(
          minimizeToTray: _minimizeToTray,
          startWithWindows: _startWithWindows,
        );

        await _appServiceManager.updateConfig(updatedConfig);
        developer.log(
          'Windows settings saved during onboarding: minimizeToTray=$_minimizeToTray, startWithWindows=$_startWithWindows',
          name: 'OnboardingScreen',
        );
      }
    } catch (e) {
      developer.log(
        'Error saving Windows settings: $e',
        name: 'OnboardingScreen',
      );
    }
  }

  Widget _buildStepContainer(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = 640.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentStep = index;
            });
            _saveCurrentStep(index);
          },
          children: _getSteps(),
        ),
      ),
    );
  }

  List<Widget> _getSteps() {
    final size = MediaQuery.sizeOf(context);
    final isSmallScreen = size.width < 600;

    if (Platform.isAndroid) {
      return [
        _buildWelcomeStep(size, isSmallScreen),
        _buildConnectionStep(size, isSmallScreen),
        _buildPermissionsStep(size, isSmallScreen),
        _buildNonWindowsLoggingStep(size, isSmallScreen),
        _buildFinishStep(size, isSmallScreen),
      ];
    } else if (Platform.isWindows) {
      return [
        _buildWelcomeStep(size, isSmallScreen),
        _buildConnectionStep(size, isSmallScreen),
        _buildVRChatLoggingStep(size, isSmallScreen),
        _buildWindowsSettingsStep(size, isSmallScreen),
        _buildFinishStep(size, isSmallScreen),
      ];
    } else {
      return [
        _buildWelcomeStep(size, isSmallScreen),
        _buildConnectionStep(size, isSmallScreen),
        _buildNonWindowsLoggingStep(size, isSmallScreen),
        _buildFinishStep(size, isSmallScreen),
      ];
    }
  }

  Widget _buildWelcomeStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.2),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.04),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: Column(
                    children: [
                      Text(
                        'Welcome to GalleVR',
                        style: Theme.of(
                          context,
                        ).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your VR photos, organized and accessible',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.secondaryTextColor,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.05),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: AppCard(
                    child: Column(
                      children: [
                        _buildFeatureRow(
                          icon: Icons.photo_library_rounded,
                          iconColor: AppTheme.iconPhotos,
                          title: 'Organize Your VR Memories',
                          description:
                              'GalleVR automatically sorts your VRChat photos by world, friends, and more.',
                        ),
                        const Divider(
                          height: 1,
                          color: AppTheme.cardBorderColor,
                        ),
                        _buildFeatureRow(
                          icon: Icons.search_rounded,
                          iconColor: AppTheme.iconFeed,
                          title: 'Find Photos Instantly',
                          description:
                              'No more endless scrolling through folders with VR controllers.',
                        ),
                        const Divider(
                          height: 1,
                          color: AppTheme.cardBorderColor,
                        ),
                        _buildFeatureRow(
                          icon: Icons.shield_rounded,
                          iconColor: AppTheme.iconPlayers,
                          title: 'Private & Secure',
                          description:
                              'Your photos stay private unless you choose to share them.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.05),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: TintedButton(
                    onPressed: _nextStep,
                    label: 'Get Started',
                    appendIcon: Icons.arrow_forward_rounded,
                    color: _brandPurple,
                    width: double.infinity,
                    height: 48,
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              Text(
                'Storage Permissions',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.04),

              _buildPermissionsCard(),

              SizedBox(height: size.height * 0.05),

              Row(
                children: [
                  Expanded(
                    child: TintedButton.neutral(
                      onPressed: _previousStep,
                      label: 'Back',
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TintedButton(
                      onPressed: _permissionsGranted ? _nextStep : null,
                      label: 'Next',
                      color: _brandPurple,
                      height: 48,
                      loading: _isLoading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              Text(
                'Unlock the Full Experience',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'GalleVR is your personal and social VR hub',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.secondaryTextColor,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.05),

              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.public_rounded,
                          color: _brandPurple,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Web & Social Features',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Linking your VRChat account unlocks the core GalleVR experience:',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBenefitItem(
                      'Private by Default: You control your photos',
                    ),
                    _buildBenefitItem(
                      'Social Feed: See what your friends are up to',
                    ),
                    _buildBenefitItem(
                      'Profiles: Showcase your favorite VR moments',
                    ),
                    _buildBenefitItem(
                      'Advanced Sorting: By world, friends, and more',
                    ),
                    _buildBenefitItem(
                      'Access Anywhere: Browse gallery anywhere',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Ready to link your VRChat account?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Note: Linking will NOT automatically sync existing photos. Your gallery remains 100% private until shared.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: size.height * 0.05),

              TintedButton(
                onPressed: _proceedToWebConnection,
                label: 'Link VRChat Account',
                appendIcon: Icons.link_rounded,
                color: _brandPurple,
                width: double.infinity,
                height: 48,
              ),

              const SizedBox(height: 12),

              TintedButton.neutral(
                onPressed: _previousStep,
                label: 'Back',
                width: double.infinity,
                height: 48,
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: _showSkipConnectionDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.secondaryTextColor,
                  ),
                  child: const Text('Continue without Linking'),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVRChatLoggingStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              Text(
                'VRChat Logging',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.04),

              _buildLoggingCard(),

              if (!_isVRChatLoggingEnabled) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.tint(AppTheme.warningColor, 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.warningColor,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'VRChat full logging is required to process and organize your photos. Please enable it to continue.',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: size.height * 0.05),

              Row(
                children: [
                  Expanded(
                    child: TintedButton.neutral(
                      onPressed: _previousStep,
                      label: 'Back',
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child:
                        _isVRChatLoggingEnabled
                            ? TintedButton(
                              onPressed: _nextStep,
                              label: 'Next',
                              color: _brandPurple,
                              height: 48,
                            )
                            : TintedButton.neutral(
                              onPressed: _showSkipLoggingDialog,
                              label: 'Skip Logging',
                              height: 48,
                            ),
                  ),
                ],
              ),
              if (!_isVRChatLoggingEnabled) ...[
                const SizedBox(height: 12),
                const Text(
                  'Full logging is recommended for photo tagging',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoggingCard() {
    final accentColor =
        _isVRChatLoggingEnabled ? AppTheme.successColor : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      accent: _isVRChatLoggingEnabled ? AppTheme.successColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isVRChatLoggingEnabled
                    ? Icons.check_circle_rounded
                    : Icons.settings_rounded,
                color: accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'VRChat Full Logging',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Without VRChat full logging enabled, GalleVR cannot process your photos or extract metadata like world names and player lists.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 14),
          _buildBenefitItem(
            'Required for automatic world name detection',
            iconColor: accentColor,
          ),
          _buildBenefitItem(
            'Required for player tagging in photos',
            iconColor: accentColor,
          ),
          _buildBenefitItem(
            'Required for enhanced search capabilities',
            iconColor: accentColor,
          ),
          const SizedBox(height: 20),
          if (!_isVRChatLoggingEnabled)
            TintedButton(
              onPressed: _isEnablingLogging ? null : _enableVRChatLogging,
              label: 'Enable Full Logging',
              color: _brandPurple,
              width: double.infinity,
              height: 44,
              loading: _isEnablingLogging,
            )
          else if (_isVRChatRunning && _justEnabledLogging)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.successColor,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Full logging enabled',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.tint(AppTheme.warningColor, 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.warningColor,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'VRChat is running. Please restart the game for logging to take effect.',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppTheme.successColor),
                SizedBox(width: 8),
                Text(
                  'Full logging enabled',
                  style: TextStyle(
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String text, {Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: iconColor ?? _brandPurple,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.bodyTextColor,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsSettingsStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              Text(
                'Windows Settings',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.04),

              _buildWindowsSettingsCard(),

              SizedBox(height: size.height * 0.05),

              Row(
                children: [
                  Expanded(
                    child: TintedButton.neutral(
                      onPressed: _previousStep,
                      label: 'Back',
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TintedButton(
                      onPressed: _nextStep,
                      label: 'Next',
                      color: _brandPurple,
                      height: 48,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindowsSettingsCard() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings_rounded, color: _brandPurple, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Application Behavior',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Configure how GalleVR behaves on your Windows system:',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 16),

          _buildCustomSwitchRow(
            title: 'Minimize to System Tray',
            subtitle: 'Keep GalleVR running in the background when closed',
            value: _minimizeToTray,
            onChanged: (value) {
              setState(() {
                _minimizeToTray = value;
              });
            },
            activeColor: _brandPurple,
          ),

          _buildCustomSwitchRow(
            title: 'Start with Windows',
            subtitle: 'Automatically launch GalleVR on system startup',
            value: _startWithWindows,
            onChanged: (value) {
              setState(() {
                _startWithWindows = value;
              });
            },
            activeColor: _brandPurple,
          ),

          const SizedBox(height: 12),
          const Text(
            'Note: You can change these settings later in the app settings.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard() {
    final accentColor =
        _permissionsGranted ? AppTheme.successColor : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      accent: _permissionsGranted ? AppTheme.successColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _permissionsGranted
                    ? Icons.check_circle_rounded
                    : Icons.folder_rounded,
                color: accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Storage Permissions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'GalleVR needs access to your photos and documents to organize your VRChat photos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 20),
          if (!_permissionsGranted)
            TintedButton(
              onPressed: _isLoading ? null : _requestPermissions,
              label: 'Grant Permissions',
              color: _brandPurple,
              width: double.infinity,
              height: 44,
              loading: _isLoading,
            )
          else
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: AppTheme.successColor),
                SizedBox(width: 8),
                Text(
                  'Permissions granted',
                  style: TextStyle(
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNonWindowsLoggingStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.05),

              Text(
                'VRChat Logging',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.04),

              _buildNonWindowsLoggingCard(),

              if (!_isLogsDirectoryAvailable && !_isCheckingLogsDirectory) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.tint(AppTheme.warningColor, 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.warningColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          Platform.isAndroid
                              ? 'VRChat logging is off. You must enable logging in VRChat settings first, and then restart VRChat for logging to take effect before you can continue.'
                              : 'Please enable VRChat full logging to continue setup.',
                          style: const TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: size.height * 0.05),

              Row(
                children: [
                  Expanded(
                    child: TintedButton.neutral(
                      onPressed: _previousStep,
                      label: 'Back',
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child:
                        _isLogsDirectoryAvailable
                            ? TintedButton(
                              onPressed: _nextStep,
                              label: 'Next',
                              color: _brandPurple,
                              height: 48,
                            )
                            : TintedButton.neutral(
                              onPressed: _showSkipLoggingDialog,
                              label: 'Skip Logging',
                              height: 48,
                            ),
                  ),
                ],
              ),

              if (!_isLogsDirectoryAvailable && !_isCheckingLogsDirectory) ...[
                const SizedBox(height: 12),
                const Text(
                  'Full logging is recommended for photo tagging',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNonWindowsLoggingCard() {
    final accentColor =
        _isLogsDirectoryAvailable ? AppTheme.successColor : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      accent: _isLogsDirectoryAvailable ? AppTheme.successColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isLogsDirectoryAvailable
                    ? Icons.check_circle_rounded
                    : _isCheckingLogsDirectory
                    ? Icons.refresh_rounded
                    : Icons.settings_rounded,
                color: accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'VRChat Full Logging',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'GalleVR needs VRChat\'s full logging enabled to extract detailed information about photos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            'Enables automatic world name detection',
            iconColor: accentColor,
          ),
          _buildBenefitItem(
            'Enables player tagging in photos',
            iconColor: accentColor,
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBase,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppTheme.cardBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: _brandPurple,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Manual Setup Required',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'To enable full logging in VRChat:',
                  style: TextStyle(
                    color: AppTheme.bodyTextColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInstructionStep('1. Open VRChat & Go to Settings'),
                _buildInstructionStep('2. Navigate to Debug tab'),
                _buildInstructionStep('3. Set Logging to "Full"'),
                _buildInstructionStep('4. Restart VRChat application'),
                const SizedBox(height: 12),
                TintedButton(
                  onPressed:
                      _isCheckingLogsDirectory ? null : _recheckLogsDirectory,
                  label: 'Check Again',
                  color: _brandPurple,
                  width: double.infinity,
                  dense: true,
                  loading: _isCheckingLogsDirectory,
                ),
              ],
            ),
          ),

          if (_isLogsDirectoryAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.successColor,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Full logging detected',
                    style: TextStyle(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '  • ',
            style: TextStyle(color: _brandPurple, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recheckLogsDirectory() async {
    await _checkLogsDirectoryAvailability();
  }

  Future<void> _showSkipLoggingDialog() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.modalDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.warningColor,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Skip Logging?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Full logging is required for photo tagging and world detection.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Without it, GalleVR cannot:\n• Automatically detect world names\n• Tag friends in your photos',
                    style: TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Skip setup anyway?',
                    style: TextStyle(
                      color: AppTheme.bodyTextColor,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TintedButton.neutral(
                        onPressed: () => Navigator.of(context).pop(false),
                        label: 'Go Back',
                        dense: true,
                      ),
                      const SizedBox(width: 10),
                      TintedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        label: 'Continue (Limited)',
                        color: AppTheme.warningColor,
                        dense: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
    if (shouldSkip == true) _nextStep();
  }

  Future<void> _showSkipConnectionDialog() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.modalDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skip Account Linking?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Without linking, you lose access to Social Feeds, Profiles and sync.\n\nContinue without linking?',
                    style: TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TintedButton.neutral(
                        onPressed: () => Navigator.of(context).pop(false),
                        label: 'Go Back',
                        dense: true,
                      ),
                      const SizedBox(width: 10),
                      TintedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        label: 'Continue (Limited)',
                        color: AppTheme.warningColor,
                        dense: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
    if (shouldSkip == true) await _proceedToLocalOnly();
  }

  Widget _buildFinishStep(Size size, bool isSmallScreen) {
    return _buildStepContainer(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 24 : 40,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.1),
              const Icon(
                Icons.check_rounded,
                color: AppTheme.successColor,
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                'Setup Complete!',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'You\'re all set to start using GalleVR. Your VR memories are ready to be organized.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.secondaryTextColor,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              if (!_isVRChatLoggingEnabled && !Platform.isWindows) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.tint(AppTheme.warningColor, 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppTheme.warningColor,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Note: World detection and tagging are disabled because logging is off.',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: size.height * 0.08),
              TintedButton(
                onPressed: _finishOnboarding,
                label:
                    _wantsToLinkAccount
                        ? 'Link Account & Start'
                        : 'Start Using GalleVR',
                appendIcon: Icons.arrow_forward_rounded,
                color: _brandPurple,
                width: double.infinity,
                height: 48,
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _previousStep,
                child: const Text(
                  'Back to Review Settings',
                  style: TextStyle(color: AppTheme.secondaryTextColor),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
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
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.cardBorderColor)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: onChanged != null ? () => onChanged(!value) : null,
          hoverColor: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 10 : 14),
            child: Row(
              children: [
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
                const SizedBox(width: 16),
                AppSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
