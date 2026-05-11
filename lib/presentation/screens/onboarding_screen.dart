import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/vrchat_registry_service.dart';
import '../../core/platform/platform_service_factory.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/vrchat_service.dart';
import 'home_screen.dart';
import 'verification_screen.dart';
import '../widgets/app_card.dart';

// Onboarding screen shown on first app launch
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

  // VRChat logging status (Non-Windows platforms)
  bool _isLogsDirectoryAvailable = false;
  bool _isCheckingLogsDirectory = false;

  // Windows settings
  bool _minimizeToTray = true;
  bool _startWithWindows = true;

  int _currentStep = 0;

  final PageController _pageController = PageController();

  static const Color _brandPurple = Color(0xFF8B5CF6);
  static const Color _brandMagenta = Color(0xFFEC4899);

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

    // Only check permissions on Android
    if (Platform.isAndroid) {
      _checkPermissions();
    } else {
      // On Windows, permissions are always considered granted
      setState(() {
        _permissionsGranted = true;
      });
    }

    _initializeVRChatService();

    // Check VRChat logging status on Windows
    if (Platform.isWindows) {
      _checkVRChatLoggingStatus();
    } else {
      // Check logs directory availability on non-Windows platforms
      _checkLogsDirectoryAvailability();
    }
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
    if (Platform.isWindows) return; // Only for non-Windows platforms

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
    final maxStep = Platform.isAndroid ? 3 : (Platform.isWindows ? 4 : 3);
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
    if (Platform.isWindows) {
      await _saveWindowsSettings();
    }

    await _appServiceManager.markOnboardingComplete();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const VerificationScreen()),
      );
    }
  }

  Future<void> _proceedToLocalOnly() async {
    if (Platform.isWindows) {
      await _saveWindowsSettings();
    }

    await _appServiceManager.markOnboardingComplete();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const HomeScreen(initialTabIndex: 0),
        ),
      );
    }
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
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;
    final isAndroid = Platform.isAndroid;

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
          },
          children:
              isAndroid
                  ? [
                    _buildWelcomeStep(size, isSmallScreen),
                    _buildPermissionsStep(size, isSmallScreen),
                    _buildNonWindowsLoggingStep(size, isSmallScreen),
                    _buildConnectionStep(size, isSmallScreen),
                  ]
                  : Platform.isWindows
                  ? [
                    _buildWelcomeStep(size, isSmallScreen),
                    _buildVRChatLoggingStep(size, isSmallScreen),
                    _buildWindowsSettingsStep(size, isSmallScreen),
                    _buildConnectionStep(size, isSmallScreen),
                  ]
                  : [
                    _buildWelcomeStep(size, isSmallScreen),
                    _buildNonWindowsLoggingStep(size, isSmallScreen),
                    _buildConnectionStep(size, isSmallScreen),
                  ],
        ),
      ),
    );
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
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                            boxShadow: [
                              BoxShadow(
                                color: _brandPurple.withAlpha(48),
                                blurRadius: 60,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                        ),
                        Image.asset(
                          'assets/images/logo.png',
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                      ],
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
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 4,
                        width: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_brandPurple, _brandMagenta],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your VR photos, organized and accessible',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
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
                  child: _buildFeatureCard(
                    icon: Icons.photo_library_rounded,
                    title: 'Organize Your VR Memories',
                    description:
                        'GalleVR automatically sorts your VRChat photos by world, friends, and more.',
                  ),
                ),
              ),

              const SizedBox(height: 16),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: _buildFeatureCard(
                    icon: Icons.search_rounded,
                    title: 'Find Photos Instantly',
                    description:
                        'No more endless scrolling through folders with VR controllers.',
                  ),
                ),
              ),

              const SizedBox(height: 16),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: _buildFeatureCard(
                    icon: Icons.shield_rounded,
                    title: 'Private & Secure',
                    description:
                        'Your photos stay private unless you choose to share them.',
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.06),

              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(_slideAnimation),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Get Started'.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
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
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPurple, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'GalleVR needs access to your media files',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.06),

              _buildPermissionsCard(),

              SizedBox(height: size.height * 0.06),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _permissionsGranted ? _nextStep : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandPurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _brandPurple.withAlpha(77),
                          disabledForegroundColor: Colors.white.withOpacity(
                            0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Next',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                      ),
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
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPurple, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'GalleVR is your personal and social VR hub',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.06),

              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.public_rounded,
                            color: _brandPurple,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Web & Social Features',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Linking your VRChat account unlocks the core GalleVR experience:',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.7),
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
                    const SizedBox(height: 24),
                    const Text(
                      'Ready to link your VRChat account?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Note: Linking will NOT automatically sync existing photos. Your gallery remains 100% private until shared.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: size.height * 0.06),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _proceedToWebConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Link VRChat Account'.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.link_rounded, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _showSkipConnectionDialog,
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
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
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPurple, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enable full logging for photo metadata tagging',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.06),

              _buildLoggingCard(),

              if (!_isVRChatLoggingEnabled) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 152, 0, 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 152, 0, 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'VRChat full logging is required to process and organize your photos. Please enable it to continue.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: size.height * 0.06),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isVRChatLoggingEnabled ? _nextStep : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandPurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _brandPurple.withAlpha(77),
                          disabledForegroundColor: Colors.white.withOpacity(
                            0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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

  Widget _buildLoggingCard() {
    final accentColor = _isVRChatLoggingEnabled ? Colors.green : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      borderColor:
          _isVRChatLoggingEnabled ? Colors.green.withOpacity(0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isVRChatLoggingEnabled
                      ? Icons.check_circle_rounded
                      : Icons.settings_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'VRChat Full Logging',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Without VRChat full logging enabled, GalleVR cannot process your photos or extract metadata like world names and player lists.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isEnablingLogging ? null : _enableVRChatLogging,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child:
                    _isEnablingLogging
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          'Enable Full Logging',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            )
          else if (_isVRChatRunning && _justEnabledLogging)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Full logging enabled',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 152, 0, 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 152, 0, 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'VRChat is running. Please restart the game for logging to take effect.',
                          style: TextStyle(
                            color: Colors.orange,
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
                Icon(Icons.check_circle_outline, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Full logging enabled',
                  style: TextStyle(
                    color: Colors.green,
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
          Icon(Icons.check_circle, color: iconColor ?? _brandPurple, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color.fromRGBO(255, 255, 255, 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _brandPurple, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.6),
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
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPurple, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Configure how GalleVR behaves on your system',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.06),

              _buildWindowsSettingsCard(),

              SizedBox(height: size.height * 0.06),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: _brandPurple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Application Behavior',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Configure how GalleVR behaves on your Windows system:',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 16),
          const Text(
            'Note: You can change these settings later in the app settings.',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Color.fromRGBO(255, 255, 255, 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard() {
    final accentColor = _permissionsGranted ? Colors.green : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      borderColor: _permissionsGranted ? Colors.green.withOpacity(0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _permissionsGranted
                      ? Icons.check_circle_rounded
                      : Icons.folder_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Storage Permissions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'GalleVR needs access to your photos and documents to organize your VRChat photos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          if (!_permissionsGranted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _requestPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          'Grant Permissions',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            )
          else
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Permissions granted',
                  style: TextStyle(
                    color: Colors.green,
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
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPurple, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enable full logging for photo metadata tagging',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: size.height * 0.06),

              _buildNonWindowsLoggingCard(),

              if (!_isLogsDirectoryAvailable && !_isCheckingLogsDirectory) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 152, 0, 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 152, 0, 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Please enable VRChat full logging to continue setup.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: size.height * 0.06),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLogsDirectoryAvailable ? _nextStep : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandPurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _brandPurple.withAlpha(77),
                          disabledForegroundColor: Colors.white.withOpacity(
                            0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (!_isLogsDirectoryAvailable && !_isCheckingLogsDirectory) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 32,
                  child: TextButton(
                    onPressed: _showSkipLoggingDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Skip (Not Recommended)'),
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
    final accentColor = _isLogsDirectoryAvailable ? Colors.green : _brandPurple;

    return AppCard(
      padding: const EdgeInsets.all(24),
      borderColor:
          _isLogsDirectoryAvailable ? Colors.green.withOpacity(0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isLogsDirectoryAvailable
                      ? Icons.check_circle_rounded
                      : _isCheckingLogsDirectory
                      ? Icons.refresh_rounded
                      : Icons.settings_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'VRChat Full Logging',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'GalleVR needs VRChat\'s full logging enabled to extract detailed information about photos.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withOpacity(0.7),
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
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: _brandPurple,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Manual Setup Required',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'To enable full logging in VRChat:',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.8),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInstructionStep('1. Open VRChat & Go to Settings'),
                _buildInstructionStep('2. Navigate to Debug tab'),
                _buildInstructionStep('3. Set Logging to "Full"'),
                _buildInstructionStep('4. Restart VRChat application'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _isCheckingLogsDirectory ? null : _recheckLogsDirectory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child:
                        _isCheckingLogsDirectory
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Text(
                              'Check Again',
                              style: TextStyle(fontSize: 13),
                            ),
                  ),
                ),
              ],
            ),
          ),

          if (_isLogsDirectoryAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Full logging detected',
                    style: TextStyle(
                      color: Colors.green,
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
                color: Color.fromRGBO(255, 255, 255, 0.7),
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
          (context) => AlertDialog(
            backgroundColor: const Color.fromRGBO(20, 20, 30, 1),
            title: const Text(
              'Skip Logging Setup?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Without full logging enabled, GalleVR cannot auto-detect worlds or tag players.\n\nSkip setup anyway?',
              style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Skip Anyway'),
              ),
            ],
          ),
    );
    if (shouldSkip == true) _nextStep();
  }

  Future<void> _showSkipConnectionDialog() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color.fromRGBO(20, 20, 30, 1),
            title: const Text(
              'Skip Account Linking?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Without linking, you lose access to Social Feeds, Profiles and sync.\n\nContinue without linking?',
              style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Go Back'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Continue (Limited)'),
              ),
            ],
          ),
    );
    if (shouldSkip == true) await _proceedToLocalOnly();
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
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.38),
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
}
