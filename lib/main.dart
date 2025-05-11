import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'data/services/app_service_manager.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await AppServiceManager().initialize();
  runApp(const GalleVRApp());
}

class GalleVRApp extends StatefulWidget {
  const GalleVRApp({super.key});

  @override
  State<GalleVRApp> createState() => _GalleVRAppState();
}

class _GalleVRAppState extends State<GalleVRApp> {
  final AppServiceManager _appServiceManager = AppServiceManager();
  bool _isLoading = true;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final onboardingComplete = await _appServiceManager.isOnboardingComplete();

    if (mounted) {
      setState(() {
        _showOnboarding = !onboardingComplete;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GalleVR',
      theme: AppTheme.getLightTheme(),
      darkTheme: AppTheme.getDarkTheme(),
      themeMode: ThemeMode.dark,
      home: _isLoading
          ? const _LoadingScreen()
          : (_showOnboarding ? const OnboardingScreen() : const HomeScreen()),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withAlpha(38),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/square.png',
                  width: 80,
                  height: 80,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
