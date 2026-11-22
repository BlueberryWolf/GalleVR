import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/image/image_cache_service.dart';
import 'core/services/linux_service.dart';
import 'core/services/memory_manager.dart';
import 'core/services/prefs_sanitizer.dart';
import 'core/services/windows_service.dart';
import 'data/services/app_service_manager.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/widgets/app_wrapper.dart';

class AppArgs {
  static const String startMinimized = '--start-minimized';

  static bool hasStartMinimized(List<String> args) {
    return args.contains(startMinimized);
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await sanitizeSharedPreferencesFile();
  ImageCacheService.applyMemoryLimits();
  if (Platform.isAndroid || Platform.isIOS) {
    FlutterForegroundTask.initCommunicationPort();
  }

  final bool isDesktop = Platform.isWindows || Platform.isLinux;
  final bool shouldStartMinimized = isDesktop && AppArgs.hasStartMinimized(args);

  if (shouldStartMinimized) {
    developer.log('App starting headless/minimized', name: 'GalleVRApp');
    if (Platform.isWindows) {
      WindowsService().isHidden.value = true;
    } else if (Platform.isLinux) {
      LinuxService().isHidden.value = true;
    }
  }

  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  final appServiceManager = AppServiceManager();
  final onboardingFuture = appServiceManager.isOnboardingComplete();
  unawaited(appServiceManager.initialize());

  if (shouldStartMinimized) {
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        if (Platform.isWindows) {
          await WindowsService().showStartMinimizedNotification();
        } else if (Platform.isLinux) {
          await LinuxService().showStartMinimizedNotification();
        }
      } catch (e) {
        developer.log(
          'Error showing start minimized notification: $e',
          name: 'GalleVRApp',
        );
      }
    });
  }

  runWidget(
    _GalleVRViewHost(
      args: args,
      onboardingFuture: onboardingFuture,
    ),
  );
}

class _GalleVRViewHost extends StatefulWidget {
  final List<String> args;
  final Future<bool> onboardingFuture;

  const _GalleVRViewHost({
    required this.args,
    required this.onboardingFuture,
  });

  @override
  State<_GalleVRViewHost> createState() => _GalleVRViewHostState();
}

class _GalleVRViewHostState extends State<_GalleVRViewHost>
    with WidgetsBindingObserver {
  bool? _onboardingComplete;
  final ValueNotifier<bool> _mobileHidden = ValueNotifier<bool>(false);
  late List<FlutterView> _views;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _views = WidgetsBinding.instance.platformDispatcher.views.toList();

    widget.onboardingFuture.then((complete) {
      if (mounted) {
        setState(() {
          _onboardingComplete = complete;
        });
      }
    }).catchError((Object e) {
      developer.log('Error reading onboarding state: $e', name: 'GalleVRApp');
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mobileHidden.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final currentViews =
        WidgetsBinding.instance.platformDispatcher.views.toList();
    if (!_sameViews(_views, currentViews)) {
      setState(() {
        _views = currentViews;
      });
    }
  }

  bool _sameViews(List<FlutterView> a, List<FlutterView> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].viewId != b[i].viewId) return false;
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid || Platform.isIOS) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        developer.log(
          'Mobile app hidden/paused: tearing down UI tree and purging caches',
          name: 'GalleVRApp',
        );
        _mobileHidden.value = true;
        unawaited(MemoryManager.purgeUiResources());
      } else if (state == AppLifecycleState.resumed) {
        developer.log(
          'Mobile app resumed: restoring UI tree and image cache limits',
          name: 'GalleVRApp',
        );
        MemoryManager.restoreUiResources();
        _mobileHidden.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_views.isEmpty) {
      return const ViewCollection(views: <Widget>[]);
    }

    final isDesktop = Platform.isWindows || Platform.isLinux;
    final visibilityNotifier =
        Platform.isWindows
            ? WindowsService().isHidden
            : Platform.isLinux
            ? LinuxService().isHidden
            : _mobileHidden;

    return ViewCollection(
      views: [
        for (final flutterView in _views)
          View(
            key: ValueKey<int>(flutterView.viewId),
            view: flutterView,
            child: ValueListenableBuilder<bool>(
              valueListenable: visibilityNotifier,
              builder: (context, isHidden, _) {
                if (isHidden) {
                  return const SizedBox.shrink();
                }
                return _GalleVRAppContent(
                  isDesktop: isDesktop,
                  onboardingComplete: _onboardingComplete,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _GalleVRAppContent extends StatefulWidget {
  final bool isDesktop;
  final bool? onboardingComplete;

  const _GalleVRAppContent({
    required this.isDesktop,
    required this.onboardingComplete,
  });

  @override
  State<_GalleVRAppContent> createState() => _GalleVRAppContentState();
}

class _GalleVRAppContentState extends State<_GalleVRAppContent> {
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingComplete = widget.onboardingComplete;

    if (onboardingComplete == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brandPurple),
              ),
            ),
          ),
        ),
      );
    }

    final Widget home =
        onboardingComplete ? const HomeScreen() : const OnboardingScreen();

    return MaterialApp(
      title: 'GalleVR',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: AppWrapper(
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (keyEvent) async {
            if (keyEvent is KeyDownEvent &&
                keyEvent.logicalKey == LogicalKeyboardKey.f4 &&
                HardwareKeyboard.instance.isAltPressed) {
              if (widget.isDesktop) {
                developer.log(
                  'Alt+F4 detected, exiting application',
                  name: 'GalleVRApp',
                );
                try {
                  await AppServiceManager()
                      .handleWindowClose(forceExit: true)
                      .timeout(
                        const Duration(milliseconds: 200),
                        onTimeout: () => false,
                      );
                } catch (e) {
                  developer.log(
                    'Error during normal exit: $e',
                    name: 'GalleVRApp',
                  );
                }
                exit(0);
              } else {
                SystemNavigator.pop();
              }
            }
          },
          child: home,
        ),
      ),
    );
  }
}
