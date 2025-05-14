import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/vrchat_registry_service.dart';
import '../../data/services/app_service_manager.dart';
import '../../data/services/vrchat_service.dart';
import 'home_screen.dart';
import 'verification_screen.dart';

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

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  bool _isLoading = false;
  bool _permissionsGranted = false;
  bool _isVRChatLoggingEnabled = false;
  bool _isEnablingLogging = false;
  bool _isVRChatRunning = false;
  bool _justEnabledLogging = false;

  // Windows settings
  bool _minimizeToTray = true;
  bool _startWithWindows = false;

  int _currentStep = 0;

  final PageController _pageController = PageController();

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
    }
  }

  Future<void> _checkVRChatLoggingStatus() async {
    developer.log(
      'Checking VRChat logging status',
      name: 'OnboardingScreen',
    );

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

      // Check if VRChat is running
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

      // Use the context-aware method to request permissions during onboarding
      final granted =
          await _permissionService.requestStoragePermissions(context);

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
    // For Windows, add extra steps for VRChat logging and Windows settings
    final maxStep = Platform.isAndroid ? 2 : (Platform.isWindows ? 3 : 1);
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
    // Save Windows settings if on Windows
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
    // Save Windows settings if on Windows
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

  // Save Windows settings to config
  Future<void> _saveWindowsSettings() async {
    try {
      // Load current config
      final currentConfig = _appServiceManager.config;
      if (currentConfig != null) {
        // Create updated config with Windows settings
        final updatedConfig = currentConfig.copyWith(
          minimizeToTray: _minimizeToTray,
          startWithWindows: _startWithWindows,
        );

        // Save the updated config
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0a0a12),
                  Color(0xFF0f0f1a),
                  Color(0xFF0a0a12),
                ],
              ),
            ),
          ),

          Positioned(
            top: size.height * 0.1,
            right: -size.width * 0.2,
            child: _buildGlowingOrb(
              size.width * 0.5,
              AppTheme.primaryColor.withAlpha(8),
            ),
          ),
          Positioned(
            bottom: -size.height * 0.1,
            left: -size.width * 0.3,
            child: _buildGlowingOrb(
              size.width * 0.6,
              AppTheme.primaryLightColor.withAlpha(5),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppTheme.primaryColor.withAlpha(51),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentStep = index;
                });
              },
              children: isAndroid
                ? [
                    _buildWelcomeStep(size, isSmallScreen),
                    _buildPermissionsStep(size, isSmallScreen),
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
                      _buildConnectionStep(size, isSmallScreen),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep(Size size, bool isSmallScreen) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 48,
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
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withAlpha(38),
                              blurRadius: 50,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),

                      Image.asset(
                        'assets/images/square.png',
                        width: 100,
                        height: 100,
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
                    ShaderMask(
                      shaderCallback:
                          (bounds) => LinearGradient(
                            colors: [
                              AppTheme.primaryLightColor,
                              AppTheme.primaryColor,
                              AppTheme.primaryDarkColor,
                            ],
                          ).createShader(bounds),
                      child: Text(
                        'Welcome to GalleVR',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 28 : 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    SizedBox(height: size.height * 0.02),

                    Text(
                      'Your VR photos, organized and accessible',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        color: Color.fromRGBO(255, 255, 255, 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
                child: _buildFeatureCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Organize Your VR Memories',
                  description:
                      'GalleVR automatically sorts your VRChat photos by world, friends, and more.',
                ),
              ),
            ),

            SizedBox(height: size.height * 0.02),

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

            SizedBox(height: size.height * 0.02),

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
                      backgroundColor: AppTheme.primaryColor,
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
                          'Next',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: size.height * 0.04),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsStep(Size size, bool isSmallScreen) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 48,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: size.height * 0.05),

            ShaderMask(
              shaderCallback:
                  (bounds) => LinearGradient(
                    colors: [
                      AppTheme.primaryLightColor,
                      AppTheme.primaryColor,
                      AppTheme.primaryDarkColor,
                    ],
                  ).createShader(bounds),
              child: Text(
                'Storage Permissions',
                style: TextStyle(
                  fontSize: isSmallScreen ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: size.height * 0.02),

            Text(
              'GalleVR needs access to your photos',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                color: Color.fromRGBO(255, 255, 255, 0.8),
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
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.primaryColor
                            .withAlpha(77),
                        disabledForegroundColor: const Color.fromRGBO(
                          255,
                          255,
                          255,
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
                              : const Text('Next'),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: size.height * 0.04),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStep(Size size, bool isSmallScreen) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 48,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: size.height * 0.05),

            ShaderMask(
              shaderCallback:
                  (bounds) => LinearGradient(
                    colors: [
                      AppTheme.primaryLightColor,
                      AppTheme.primaryColor,
                      AppTheme.primaryDarkColor,
                    ],
                  ).createShader(bounds),
              child: Text(
                'Connect to GalleVR',
                style: TextStyle(
                  fontSize: isSmallScreen ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: size.height * 0.02),

            Text(
              'Get the best experience with our web interface',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                color: Color.fromRGBO(255, 255, 255, 0.8),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: size.height * 0.06),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color.fromRGBO(0, 0, 0, 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorderColor, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.language,
                          color: AppTheme.primaryColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Web Interface Benefits',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The GalleVR website offers superior sorting and organization features:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color.fromRGBO(255, 255, 255, 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBenefitItem(
                    'Advanced photo sorting by world, friends, and date',
                  ),
                  _buildBenefitItem('Easy sharing with friends'),
                  _buildBenefitItem('Completely free'),
                  _buildBenefitItem('Access your photos from any device'),
                  _buildBenefitItem(
                    'Better visual experience on larger screens',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Would you like to connect to the GalleVR website?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

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
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _proceedToWebConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Connect to Website',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: _proceedToLocalOnly,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Skip (Local Only)'),
              ),
            ),

            SizedBox(height: size.height * 0.04),
          ],
        ),
      ),
    );
  }

  Widget _buildVRChatLoggingStep(Size size, bool isSmallScreen) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 48,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: size.height * 0.05),

            ShaderMask(
              shaderCallback:
                  (bounds) => LinearGradient(
                    colors: [
                      AppTheme.primaryLightColor,
                      AppTheme.primaryColor,
                      AppTheme.primaryDarkColor,
                    ],
                  ).createShader(bounds),
              child: Text(
                'VRChat Logging',
                style: TextStyle(
                  fontSize: isSmallScreen ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: size.height * 0.02),

            Text(
              'Enable full logging for photo metadata tagging',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                color: Color.fromRGBO(255, 255, 255, 0.8),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: size.height * 0.06),

            _buildLoggingCard(),

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
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Next'),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: size.height * 0.04),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggingCard() {
    final loggingColor =
        _isVRChatLoggingEnabled
            ? const Color.fromRGBO(0, 128, 0, 0.1)
            : const Color.fromRGBO(0, 0, 0, 0.2);

    final borderColor =
        _isVRChatLoggingEnabled
            ? const Color.fromRGBO(0, 128, 0, 0.3)
            : AppTheme.cardBorderColor;

    final iconBgColor =
        _isVRChatLoggingEnabled
            ? const Color.fromRGBO(0, 128, 0, 0.1)
            : AppTheme.primaryColor.withAlpha(25);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: loggingColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isVRChatLoggingEnabled
                      ? Icons.check_circle_rounded
                      : Icons.settings_rounded,
                  color:
                      _isVRChatLoggingEnabled
                          ? Colors.green
                          : AppTheme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'VRChat Full Logging',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'GalleVR needs VRChat\'s full logging enabled to extract detailed information about your photos, including world names and player lists.',
            style: TextStyle(
              fontSize: 14,
              color: Color.fromRGBO(255, 255, 255, 0.7),
            ),
          ),
          const SizedBox(height: 12),
          _buildBenefitItem('Enables automatic world name detection'),
          _buildBenefitItem('Enables player tagging in photos'),
          _buildBenefitItem('Enhances search capabilities'),
          const SizedBox(height: 20),
          if (!_isVRChatLoggingEnabled)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isEnablingLogging ? null : _enableVRChatLogging,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
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
                    color: Color.fromRGBO(255, 152, 0, 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color.fromRGBO(255, 152, 0, 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'VRChat is currently running. Please restart the game for full logging to take effect.',
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

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withAlpha(0)],
          stops: const [0.2, 1.0],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 28),
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
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color.fromRGBO(255, 255, 255, 0.7),
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 48,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: size.height * 0.05),

            ShaderMask(
              shaderCallback:
                  (bounds) => LinearGradient(
                    colors: [
                      AppTheme.primaryLightColor,
                      AppTheme.primaryColor,
                      AppTheme.primaryDarkColor,
                    ],
                  ).createShader(bounds),
              child: Text(
                'Windows Settings',
                style: TextStyle(
                  fontSize: isSmallScreen ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: size.height * 0.02),

            Text(
              'Configure how GalleVR behaves on your system',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                color: Color.fromRGBO(255, 255, 255, 0.8),
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
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Next'),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: size.height * 0.04),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowsSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: AppTheme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Application Behavior',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Configure how GalleVR behaves on your Windows system:',
            style: TextStyle(
              fontSize: 14,
              color: Color.fromRGBO(255, 255, 255, 0.7),
            ),
          ),
          const SizedBox(height: 20),

          // Minimize to tray switch
          SwitchListTile(
            title: const Text(
              'Minimize to System Tray',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Keep GalleVR running in the background when closed',
              style: TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.7),
                fontSize: 13,
              ),
            ),
            value: _minimizeToTray,
            activeColor: AppTheme.primaryColor,
            onChanged: (value) {
              setState(() {
                _minimizeToTray = value;
              });
            },
          ),

          const Divider(color: Color.fromRGBO(255, 255, 255, 0.1)),

          // Start with Windows switch
          SwitchListTile(
            title: const Text(
              'Start with Windows',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Automatically start GalleVR when Windows starts',
              style: TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.7),
                fontSize: 13,
              ),
            ),
            value: _startWithWindows,
            activeColor: AppTheme.primaryColor,
            onChanged: (value) {
              setState(() {
                _startWithWindows = value;
              });
            },
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
    final permissionColor =
        _permissionsGranted
            ? const Color.fromRGBO(0, 128, 0, 0.1)
            : const Color.fromRGBO(0, 0, 0, 0.2);

    final borderColor =
        _permissionsGranted
            ? const Color.fromRGBO(0, 128, 0, 0.3)
            : AppTheme.cardBorderColor;

    final iconBgColor =
        _permissionsGranted
            ? const Color.fromRGBO(0, 128, 0, 0.1)
            : AppTheme.primaryColor.withAlpha(25);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: permissionColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _permissionsGranted
                      ? Icons.check_circle_rounded
                      : Icons.folder_rounded,
                  color:
                      _permissionsGranted
                          ? Colors.green
                          : AppTheme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Storage Permissions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'GalleVR needs access to your photos, videos, and documents to find and organize your VR content. These permissions are only used to access your VRChat photos and related files.',
            style: TextStyle(
              fontSize: 14,
              color: Color.fromRGBO(255, 255, 255, 0.7),
            ),
          ),
          const SizedBox(height: 20),
          if (!_permissionsGranted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _requestPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
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
}


