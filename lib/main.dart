import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'data/services/app_service_manager.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'core/services/windows_service.dart';

// Command line arguments
class AppArgs {
  static const String startMinimized = '--start-minimized';

  static bool hasStartMinimized(List<String> args) {
    return args.contains(startMinimized);
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Ensure single instance on Windows
  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "GalleVR-app",
      onSecondWindow: (args) {
        // When a second instance is launched, bring the existing window to front
        developer.log('Second instance detected with args: $args', name: 'GalleVRApp');
        WindowsService().showWindow();
      }
    );
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize app services
  final appServiceManager = AppServiceManager();
  await appServiceManager.initialize();

  bool shouldStartMinimized = Platform.isWindows && AppArgs.hasStartMinimized(args);
  if (shouldStartMinimized) {
    developer.log('App will start minimized', name: 'GalleVRApp');
  }

  runApp(GalleVRApp(args: args));
}

class GalleVRApp extends StatefulWidget {
  final List<String> args;

  const GalleVRApp({super.key, this.args = const []});

  @override
  State<GalleVRApp> createState() => _GalleVRAppState();
}

class _GalleVRAppState extends State<GalleVRApp> with WidgetsBindingObserver {
  final AppServiceManager _appServiceManager = AppServiceManager();
  bool _isLoading = true;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOnboardingStatus();

    // The window visibility is now handled at the native level
    // If the app is starting minimized, show a notification after a delay
    if (Platform.isWindows && AppArgs.hasStartMinimized(widget.args)) {
      developer.log('App configured to start minimized', name: 'GalleVRApp');

      // Show a notification after a delay to ensure the app is fully initialized
      Future.delayed(Duration(seconds: 2), () async {
        try {
          await WindowsService().showStartMinimizedNotification();
        } catch (e) {
          developer.log('Error showing start minimized notification: $e', name: 'GalleVRApp');
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // this is called when the app is about to be closed
      // i don't need to do anything here as the native code will handle it
    }
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
    // Create the main app content
    Widget home = _isLoading
        ? const _LoadingScreen()
        : (_showOnboarding ? const OnboardingScreen() : const HomeScreen());

    return MaterialApp(
      title: 'GalleVR',
      theme: AppTheme.getLightTheme(),
      darkTheme: AppTheme.getDarkTheme(),
      themeMode: ThemeMode.dark,
      home: KeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKeyEvent: (keyEvent) async {
          if (keyEvent is KeyDownEvent) {
            if (keyEvent.logicalKey == LogicalKeyboardKey.f4 &&
                HardwareKeyboard.instance.isAltPressed) {
              // exit the app completely
              if (Platform.isWindows) {
                // force exit the app when Alt+F4 is pressed
                developer.log('Alt+F4 detected, exiting application', name: 'GalleVRApp');

                try {
                  // try to stop any foreground tasks directly
                  developer.log('Stopping foreground tasks', name: 'GalleVRApp');
                  await FlutterForegroundTask.stopService();
                } catch (e) {
                  developer.log('Error stopping foreground tasks: $e', name: 'GalleVRApp');
                }

                try {
                  // try the normal exit path
                  await AppServiceManager().handleWindowClose(forceExit: true);
                } catch (e) {
                  developer.log('Error during normal exit: $e', name: 'GalleVRApp');
                }

                // wtf, force exit
                developer.log('Forcing immediate exit', name: 'GalleVRApp');
                exit(0);
              } else {
                SystemNavigator.pop();
              }
            }
          }
        },
        child: home,
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
