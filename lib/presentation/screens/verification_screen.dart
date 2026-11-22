import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gallevr/presentation/screens/home_screen.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/services/tos_service.dart';
import '../../data/services/app_service_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/blurrable_qr_code.dart';
import '../widgets/app_card.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/tinted_button.dart';
import '../widgets/tos_modal.dart';
import 'onboarding_screen.dart';

class VerificationScreen extends StatefulWidget {
  final String? initialPlatform;
  final bool isLinkMode;

  const VerificationScreen({
    super.key,
    this.initialPlatform,
    this.isLinkMode = false,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final VRChatService _vrchatService = VRChatService();
  final TOSService _tosService = TOSService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _totpController = TextEditingController();
  final TextEditingController _pairCodeController = TextEditingController();

  bool _isLoading = false;
  bool _isVerified = false;
  bool _showTotpField = false;
  List<String> _twoFactorTypes = const [];
  bool _isAgeVerified = false;
  bool _showTOSModal = false;
  String _errorMessage = '';
  String _statusMessage = '';
  VerificationMethod? _selectedMethod;
  int _manualVerificationStep = 0;
  AuthData? _authData;
  String _galleryUrl = '';
  String _verificationToken = '';
  DateTime? _selectedDate;
  Map<String, dynamic>? _lookedUpAccount;
  bool _isLookingUp = false;
  String? _activePlatform;
  Timer? _pollTimer;
  bool _isPollInFlight = false;
  bool _isFriend = true;
  bool _friendCheckDone = false;
  bool _tokenCopied = false;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    _activePlatform = widget.initialPlatform;
    if (_activePlatform == 'resonite') {
      _selectedMethod = VerificationMethod.manual;
    }
    _initializeService();
  }

  @override
  void dispose() {
    _stopManualPolling();
    _copiedResetTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    _pairCodeController.dispose();
    super.dispose();
  }

  void _stopManualPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPollInFlight = false;
  }

  Future<void> _initializeService() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      try {
        await _vrchatService.initialize();
      } catch (e) {
        developer.log(
          'Non-fatal error initializing VRChat client: $e',
          name: 'VerificationScreen',
        );
      }

      final isStoredAgeVerified = await _vrchatService.loadAgeVerified();
      if (isStoredAgeVerified) {
        setState(() {
          _isAgeVerified = true;
        });
        developer.log(
          'User is already age verified from storage',
          name: 'VerificationScreen',
        );
      }

      AuthData? authData;
      final primaryAuth = await _vrchatService.loadAuthData();
      final secondaryAuth = await _vrchatService.loadAuthDataSecondary();

      if (widget.isLinkMode && widget.initialPlatform != null) {
        final targetPlatform = widget.initialPlatform;
        if (targetPlatform == 'resonite') {
          if (primaryAuth != null && primaryAuth.userId.startsWith('U-')) {
            authData = primaryAuth;
          } else if (secondaryAuth != null &&
              secondaryAuth.userId.startsWith('U-')) {
            authData = secondaryAuth;
          }
        } else {
          if (primaryAuth != null && !primaryAuth.userId.startsWith('U-')) {
            authData = primaryAuth;
          } else if (secondaryAuth != null &&
              !secondaryAuth.userId.startsWith('U-')) {
            authData = secondaryAuth;
          }
        }
      } else {
        authData = primaryAuth ?? secondaryAuth;
      }

      if (authData != null) {
        if (authData.ageVerified && !_isAgeVerified) {
          setState(() {
            _isAgeVerified = true;
          });
          await _vrchatService.setAgeVerified(true);
        }

        setState(() {
          _statusMessage = 'Checking verification status...';
        });

        final isVerified = await _vrchatService.checkVerificationStatus(
          authData,
        );

        if (isVerified) {
          setState(() {
            _isVerified = true;
            _authData = authData;
            _galleryUrl = 'https://gallevr.app/?auth=${authData!.accessKey}';
          });

          await _checkTOSStatus();
        }
      }
    } catch (e) {
      developer.log(
        'Error initializing verification service: $e',
        name: 'VerificationScreen',
      );
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter username and password';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _statusMessage = 'Logging in...';
    });

    try {
      if (_showTotpField && _totpController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your 2FA code';
          _isLoading = false;
        });
        return;
      }

      final loginResult = await _vrchatService.login(
        username: _usernameController.text,
        password: _passwordController.text,
        totpCode: _showTotpField ? _totpController.text : null,
      );

      if (loginResult.success) {
        setState(() {
          _statusMessage = 'Verifying with VRChat...';
        });

        final verificationResult = await _vrchatService
            .startAutomaticVerification(
              ageVerified: _isAgeVerified,
              onProgress: (message) {
                setState(() {
                  _statusMessage = message;
                });
              },
            );

        if (verificationResult.success && verificationResult.authData != null) {
          await _vrchatService.saveAuthData(verificationResult.authData!);

          final isVerified = await _vrchatService.checkVerificationStatus(
            verificationResult.authData!,
          );

          if (isVerified) {
            await _markAsVerified(verificationResult.authData!);
          } else {
            await Future.delayed(const Duration(seconds: 2));
            final retryVerified = await _vrchatService.checkVerificationStatus(
              verificationResult.authData!,
            );

            if (retryVerified) {
              await _markAsVerified(verificationResult.authData!);
            } else {
              setState(() {
                _errorMessage =
                    'Verification status check failed. Please try logging out and verifying again.';
              });
            }
          }
        } else {
          setState(() {
            _errorMessage =
                verificationResult.errorMessage ?? 'Verification failed';
          });
        }
      } else if (loginResult.requiresTwoFactor) {
        final isEmail = loginResult.isEmailOtp;
        final wasAlreadyShowing = _showTotpField;
        setState(() {
          _showTotpField = true;
          _twoFactorTypes = loginResult.twoFactorTypes;
          _errorMessage =
              wasAlreadyShowing
                  ? (loginResult.errorMessage ?? 'Invalid 2FA code')
                  : isEmail
                  ? 'Enter the 6-digit code sent to your email'
                  : 'Enter the 6-digit code from your authenticator app';
        });
      } else {
        setState(() {
          _errorMessage = loginResult.errorMessage ?? 'Authentication failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _submitPairCode() async {
    final code = _pairCodeController.text.replaceAll(RegExp(r'\s+'), '');
    if (code.length < 6) {
      setState(() {
        _errorMessage = 'Please enter the full 6-digit code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _statusMessage = 'Pairing with device...';
    });

    try {
      final authData = await _vrchatService.pairWithCode(
        code,
        saveAsPrimary: !widget.isLinkMode,
      );

      if (authData != null) {
        await _markAsVerified(authData);
      } else {
        setState(() {
          _errorMessage =
              'Invalid or expired pairing code. Please check and try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Check internet and try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  Future<void> _markAsVerified(AuthData baseAuth) async {
    AuthData finalAuth = baseAuth;
    try {
      final fetched = await _vrchatService.fetchMe(
        baseAuth,
        saveToStorage: false,
      );
      if (fetched != null) {
        finalAuth = fetched;
      }
    } catch (e) {
      developer.log(
        'Failed to fetch identity detail post-verifying: $e',
        name: 'VerificationScreen',
      );
    }

    final saved =
        widget.isLinkMode
            ? await _vrchatService.saveAuthDataSecondary(finalAuth)
            : await _vrchatService.saveAuthData(finalAuth);
    if (!saved) {
      if (mounted) {
        setState(() {
          if (_selectedMethod == VerificationMethod.manual) {
            _manualVerificationStep = 0;
          }
          _errorMessage =
              'Could not save your login locally. Check folder permissions or antivirus settings and try again.';
        });
      }
      return;
    }
    await AppServiceManager().refreshAuth();
    await _vrchatService.setAgeVerified(true);

    if (mounted) {
      setState(() {
        _isVerified = true;
        _authData = finalAuth;
        _galleryUrl = 'https://gallevr.app/?auth=${finalAuth.accessKey}';
      });
    }

    await _checkTOSStatus();
  }

  Future<void> _startManualVerification() async {
    if (_lookedUpAccount == null) return;

    if (!_isAgeVerified) {
      if (_selectedDate == null || !_isOver13()) {
        setState(() {
          _errorMessage = 'Please select your date of birth (must be 13+).';
        });
        return;
      }
      setState(() {
        _isAgeVerified = true;
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final lookupId =
          (_lookedUpAccount?['id'] ??
                  _lookedUpAccount?['userId'] ??
                  _usernameController.text.trim())
              .toString();
      final verificationResult = await _vrchatService.startManualVerification(
        lookupId,
        ageVerified: _isAgeVerified,
      );

      if (verificationResult.success && verificationResult.authData != null) {
        if (widget.isLinkMode) {
          await _vrchatService.saveAuthDataSecondary(
            verificationResult.authData!,
          );
        } else {
          await _vrchatService.saveAuthData(verificationResult.authData!);
        }

        if (!mounted) return;
        setState(() {
          _manualVerificationStep = 2;
          _authData = verificationResult.authData;
          _verificationToken = verificationResult.verificationToken ?? '';
          _friendCheckDone = false;
          _isFriend = true;
        });

        _checkFriendStatusQuietly(lookupId);
        _startManualPolling(verificationResult.authData!);
      } else {
        setState(() {
          _errorMessage =
              verificationResult.errorMessage ??
              'Something went wrong starting verification. Try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong starting verification. Try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _checkFriendStatusQuietly(String lookupId) async {
    try {
      var id = lookupId;
      if (_activePlatform == 'resonite' && !id.startsWith('U-')) {
        id = 'U-$id';
      }
      final friend = await _vrchatService.checkFriendStatus(id);
      if (mounted) {
        setState(() {
          _isFriend = friend;
          _friendCheckDone = true;
        });
      }
    } catch (_) {}
  }

  void _startManualPolling(AuthData pendingAuth) {
    _stopManualPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _isPollInFlight) return;
      _isPollInFlight = true;
      try {
        final verified = await _vrchatService.checkVerificationStatus(
          pendingAuth,
          forceRefresh: true,
        );
        if (verified && mounted) {
          _stopManualPolling();
          setState(() {
            _manualVerificationStep = 3;
          });
          await Future.delayed(const Duration(milliseconds: 1200));
          if (mounted) {
            await _markAsVerified(pendingAuth);
          }
        }
      } catch (_) {
      } finally {
        _isPollInFlight = false;
      }
    });
  }

  Future<void> _performAccountLookup() async {
    final text = _usernameController.text.trim();
    if (text.isEmpty || _isLookingUp) return;

    setState(() {
      _isLookingUp = true;
      _errorMessage = '';
      _lookedUpAccount = null;
    });

    try {
      final platform = _activePlatform ?? 'vrchat';
      final account = await _vrchatService.lookupAccount(
        text,
        platform: platform,
      );
      if (!mounted) return;
      setState(() {
        _lookedUpAccount = account;
        if (account != null) {
          _manualVerificationStep = 1;
        } else {
          _errorMessage =
              platform == 'resonite'
                  ? 'No Resonite account found with that name. Check spelling and try again.'
                  : 'Could not find this VRChat user. Check spelling or use their User ID.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              _activePlatform == 'resonite'
                  ? 'No Resonite account found with that name. Check spelling and try again.'
                  : 'Could not find this VRChat user. Check spelling or use their User ID.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUp = false;
        });
      }
    }
  }

  bool _isOver13() {
    if (_selectedDate == null) return false;

    final now = DateTime.now();
    final difference = now.difference(_selectedDate!);
    final age = difference.inDays ~/ 365;
    return age >= 13;
  }

  void _showDatePicker() async {
    final initialDate = DateTime.now().subtract(const Duration(days: 365 * 13));
    final firstDate = DateTime.now().subtract(const Duration(days: 365 * 100));
    final lastDate = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select your date of birth',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        if (!_isOver13()) {
          _errorMessage = 'You must be at least 13 years old to use this app.';
        } else {
          _errorMessage = '';
        }
      });
    }
  }

  Future<void> _checkTOSStatus() async {
    try {
      final needsToAcceptTOS = await _tosService.needsToAcceptTOS();

      if (needsToAcceptTOS && mounted) {
        setState(() {
          _showTOSModal = true;
        });
      }
    } catch (e) {
      developer.log(
        'Error checking TOS status: $e',
        name: 'VerificationScreen',
      );
    }
  }

  void _handleTOSAccept() {
    setState(() {
      _showTOSModal = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Terms of Service accepted. You can now use the app.'),
      ),
    );
  }

  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can still use the app, but some features may be limited.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          _activePlatform == null
              ? 'Link Account'
              : _activePlatform == 'resonite'
              ? 'Resonite Verification'
              : 'VRChat Verification',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: AppTheme.chromeColor,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.headerBorderColor),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBackNavigation,
        ),
      ),
      body: Stack(
        children: [
          _isVerified
              ? _buildVerifiedView()
              : Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isPicker =
                          _activePlatform == null || _selectedMethod == null;
                      final isManual =
                          _selectedMethod == VerificationMethod.manual;
                      final double contentMaxWidth =
                          _activePlatform == null
                              ? 960
                              : _selectedMethod == null
                              ? 820
                              : isManual
                              ? 480
                              : 560;
                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth > 640 ? 32 : 16,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 48).clamp(
                              0.0,
                              double.infinity,
                            ),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: contentMaxWidth,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_activePlatform == null)
                                    _buildPlatformPickerView(
                                      constraints.maxWidth > 720,
                                    )
                                  else if (_selectedMethod == null)
                                    _buildMethodSelectionLanding(
                                      constraints.maxWidth > 640,
                                    )
                                  else if (_selectedMethod ==
                                      VerificationMethod.pairCode)
                                    _buildPairCodeVerificationView()
                                  else if (_selectedMethod ==
                                      VerificationMethod.automatic)
                                    _buildAutomaticVerificationView()
                                  else
                                    _buildManualVerificationView(),
                                  if (isPicker) const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  if (_isLoading &&
                      _selectedMethod != VerificationMethod.manual)
                    Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: AppTheme.modalDecoration,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: AppTheme.brandPurple,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _statusMessage.isNotEmpty
                                    ? _statusMessage
                                    : 'Processing...',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.bodyTextColor,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),

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

  void _handleBackNavigation() {
    _stopManualPolling();
    if (_selectedMethod == VerificationMethod.manual &&
        _manualVerificationStep > 0 &&
        _manualVerificationStep < 3) {
      setState(() {
        _manualVerificationStep = _manualVerificationStep == 2 ? 1 : 0;
        _errorMessage = '';
      });
      return;
    }

    if (_activePlatform == 'resonite' && _selectedMethod != null) {
      if (widget.initialPlatform == null) {
        setState(() {
          _selectedMethod = null;
          _activePlatform = null;
          _manualVerificationStep = 0;
          _lookedUpAccount = null;
          _errorMessage = '';
        });
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    } else if (_selectedMethod != null) {
      setState(() {
        _selectedMethod = null;
        _manualVerificationStep = 0;
        _lookedUpAccount = null;
        _errorMessage = '';
      });
    } else if (_activePlatform != null && widget.initialPlatform == null) {
      setState(() {
        _activePlatform = null;
      });
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    }
  }

  Widget _buildPlatformPickerView(bool isWide) {
    final cards = [
      _buildPickerTile(
        title: 'Instant Link Code',
        description: '6-digit code from the website',
        icon: Icons.flash_on_rounded,
        color: AppTheme.primaryColor,
        isGrid: isWide,
        onTap: () {
          setState(() {
            _selectedMethod = VerificationMethod.pairCode;
            _activePlatform = 'vrchat';
            _errorMessage = '';
          });
        },
      ),
      _buildPickerTile(
        title: 'VRChat',
        imageAsset: 'assets/images/VRChat_logo.png',
        color: AppTheme.brandPurpleDeep,
        isGrid: isWide,
        onTap: () {
          setState(() {
            _activePlatform = 'vrchat';
            _errorMessage = '';
          });
        },
      ),
      _buildPickerTile(
        title: 'Resonite',
        imageAsset: 'assets/images/resonite_logo.png',
        color: AppTheme.resoniteColor,
        isGrid: isWide,
        onTap: () {
          _stopManualPolling();
          setState(() {
            _activePlatform = 'resonite';
            _selectedMethod = VerificationMethod.manual;
            _manualVerificationStep = 0;
            _lookedUpAccount = null;
            _errorMessage = '';
          });
        },
      ),
    ];

    return Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'Primary Platform',
          textAlign: isWide ? TextAlign.center : TextAlign.left,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 28),
        if (isWide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 16),
                Expanded(child: cards[1]),
                const SizedBox(width: 16),
                Expanded(child: cards[2]),
              ],
            ),
          )
        else
          Column(
            children: [
              cards[0],
              const SizedBox(height: 14),
              cards[1],
              const SizedBox(height: 14),
              cards[2],
            ],
          ),
      ],
    );
  }

  Widget _buildMethodSelectionLanding(bool isWide) {
    final cards = [
      _buildPickerTile(
        title: 'Automatic Verification',
        description: 'Sign in once and verify your status automatically',
        icon: Icons.verified_user_rounded,
        color: AppTheme.brandPurpleDeep,
        isGrid: isWide,
        onTap: () {
          setState(() {
            _selectedMethod = VerificationMethod.automatic;
            _errorMessage = '';
          });
        },
      ),
      _buildPickerTile(
        title: 'Manual Verification',
        description: 'Add a verification code to your VRChat status yourself',
        icon: Icons.edit_note_rounded,
        color: AppTheme.accentPink,
        isGrid: isWide,
        onTap: () {
          _stopManualPolling();
          setState(() {
            _selectedMethod = VerificationMethod.manual;
            _manualVerificationStep = 0;
            _lookedUpAccount = null;
            _errorMessage = '';
          });
        },
      ),
    ];

    return Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'Link VRChat',
          textAlign: isWide ? TextAlign.center : TextAlign.left,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 28),
        if (isWide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 16),
                Expanded(child: cards[1]),
              ],
            ),
          )
        else
          Column(children: [cards[0], const SizedBox(height: 14), cards[1]]),
      ],
    );
  }

  Widget _buildPickerTile({
    required String title,
    String? description,
    IconData? icon,
    String? imageAsset,
    required Color color,
    required bool isGrid,
    required VoidCallback onTap,
  }) {
    if (!isGrid) {
      return _buildActionCard(
        title: title,
        description: description,
        icon: icon,
        imageAsset: imageAsset,
        color: color,
        onTap: onTap,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        hoverColor: AppTheme.cardHoverColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            color: AppTheme.cardBackgroundColor,
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child:
                        imageAsset != null
                            ? Image.asset(
                              imageAsset,
                              width: 52,
                              height: 52,
                              fit: BoxFit.contain,
                            )
                            : Icon(
                              icon ?? Icons.flash_on_rounded,
                              size: 42,
                              color: color,
                            ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryTextColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPairCodeVerificationView() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.flash_on_rounded,
                color: AppTheme.brandPurple,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Instant Pair Code',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter the 6-digit code shown on the website.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.secondaryTextColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          if (_errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.tint(AppTheme.errorColor, 0.12),
                border: Border.all(
                  color: AppTheme.errorColor.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.errorTextColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: AppTheme.errorTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          TextField(
            controller: _pairCodeController,
            decoration: const InputDecoration(
              labelText: '6-Digit Code',
              prefixIcon: Icon(Icons.key_rounded),
              hintText: '123456',
            ),
            style: const TextStyle(
              fontSize: 20,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (val) {
              if (val.length == 6) {
                FocusScope.of(context).unfocus();
                _submitPairCode();
              }
            },
          ),
          const SizedBox(height: 20),

          TintedButton(
            onPressed: _isLoading ? null : _submitPairCode,
            label: 'Pair Now',
            color: AppTheme.brandPurple,
            width: double.infinity,
            height: 48,
            loading: _isLoading,
          ),

          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _selectedMethod = null;
                  _errorMessage = '';
                });
              },
              child: const Text(
                'Go Back',
                style: TextStyle(color: AppTheme.secondaryTextColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    String? description,
    IconData? icon,
    String? imageAsset,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        hoverColor: AppTheme.cardHoverColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            color: AppTheme.cardBackgroundColor,
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child:
                        imageAsset != null
                            ? imageAsset.endsWith('.svg')
                                ? Icon(
                                  Icons.hub_rounded,
                                  size: 28,
                                  color: color,
                                )
                                : Image.asset(
                                  imageAsset,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.contain,
                                )
                            : Icon(
                              icon ?? Icons.flash_on_rounded,
                              size: 28,
                              color: color,
                            ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryTextColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.secondaryTextColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomaticVerificationView() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                color: AppTheme.brandPurple,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Automatic Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username or Email',
              prefixIcon: Icon(Icons.person_rounded),
            ),
            enabled: !_isLoading,
            onChanged: (_) {
              if (_showTotpField) {
                setState(() {
                  _showTotpField = false;
                  _twoFactorTypes = const [];
                  _totpController.clear();
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            obscureText: true,
            enabled: !_isLoading,
            onChanged: (_) {
              if (_showTotpField) {
                setState(() {
                  _showTotpField = false;
                  _twoFactorTypes = const [];
                  _totpController.clear();
                });
              }
            },
          ),
          if (!_isAgeVerified) ...[
            const SizedBox(height: 20),
            const Divider(color: AppTheme.cardBorderColor),
            const SizedBox(height: 12),
            const Text(
              'Age Verification',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You must be at least 13 years old. Please enter your date of birth:',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              onTap: _isLoading ? null : _showDatePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBase,
                  border: Border.all(color: AppTheme.buttonBorderColor),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: AppTheme.secondaryTextColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDate != null
                          ? '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}'
                          : 'Select Date',
                      style: TextStyle(
                        color:
                            _selectedDate != null
                                ? Colors.white
                                : AppTheme.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _isOver13() ? Icons.check_circle : Icons.error,
                    color:
                        _isOver13()
                            ? AppTheme.successColor
                            : AppTheme.errorTextColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOver13() ? 'Age verified' : 'Must be at least 13',
                    style: TextStyle(
                      color:
                          _isOver13()
                              ? AppTheme.successColor
                              : AppTheme.errorTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (_showTotpField) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _totpController,
              decoration: InputDecoration(
                labelText:
                    _twoFactorTypes
                                .map((e) => e.toLowerCase())
                                .contains('emailotp') &&
                            !_twoFactorTypes
                                .map((e) => e.toLowerCase())
                                .contains('totp')
                        ? 'Email 2FA Code'
                        : 'Authenticator 2FA Code',
                hintText:
                    _twoFactorTypes
                                .map((e) => e.toLowerCase())
                                .contains('emailotp') &&
                            !_twoFactorTypes
                                .map((e) => e.toLowerCase())
                                .contains('totp')
                        ? '6-digit code from your email'
                        : '6-digit code or recovery code',
                prefixIcon: const Icon(Icons.security_rounded),
              ),
              keyboardType:
                  _twoFactorTypes
                          .map((e) => e.toLowerCase())
                          .contains('otp')
                      ? TextInputType.text
                      : TextInputType.number,
              enabled: !_isLoading,
            ),
          ],
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.tint(AppTheme.errorColor, 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(
                  color: AppTheme.errorColor.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                _errorMessage.split('\n').first,
                style: const TextStyle(
                  color: AppTheme.errorTextColor,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TintedButton(
            onPressed:
                _isLoading
                    ? null
                    : () {
                      if (!_isAgeVerified) {
                        if (_selectedDate == null || !_isOver13()) {
                          setState(() {
                            _errorMessage =
                                'Please complete age verification first.';
                          });
                          return;
                        }
                        setState(() {
                          _isAgeVerified = true;
                        });
                      }
                      _login();
                    },
            label: _showTotpField ? 'Verify Code' : 'Sign In',
            color: AppTheme.brandPurple,
            icon: Icons.login_rounded,
            width: double.infinity,
            height: 48,
            loading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildManualVerificationView() {
    final isResonite = _activePlatform == 'resonite';
    final accentColor =
        isResonite ? AppTheme.resoniteColor : AppTheme.primaryColor;

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_manualVerificationStep),
          child: switch (_manualVerificationStep) {
            0 => _buildManualFindAccountStep(isResonite, accentColor),
            1 => _buildManualConfirmStep(accentColor),
            2 => _buildManualVerifyStep(isResonite, accentColor),
            _ => _buildManualSuccessStep(),
          },
        ),
      ),
    );
  }

  Widget _buildManualFindAccountStep(bool isResonite, Color accentColor) {
    final canSearch = _usernameController.text.trim().isNotEmpty && !_isLookingUp;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            isResonite
                ? 'assets/images/resonite_logo.png'
                : 'assets/images/VRChat_logo.png',
            width: 48,
            height: 48,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.isLinkMode ? 'Link Account' : 'Sign In',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isResonite
              ? 'Enter your Resonite display name.'
              : 'Enter your VRChat username to continue.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: isResonite ? 'e.g. BlueberryWolf' : 'VRChat Username',
          ),
          enabled: !_isLookingUp,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _performAccountLookup(),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.tint(AppTheme.errorColor, 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.errorColor.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              _errorMessage.split('\n').first,
              style: const TextStyle(
                color: AppTheme.errorTextColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Material(
              color: AppTheme.buttonColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: _handleBackNavigation,
                hoverColor: AppTheme.buttonHoverColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(color: AppTheme.buttonBorderColor),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TintedButton(
                onPressed: canSearch ? _performAccountLookup : null,
                label: 'Find Account',
                color: accentColor,
                height: 48,
                loading: _isLookingUp,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualConfirmStep(Color accentColor) {
    final displayName =
        (_lookedUpAccount?['displayName'] as String?) ?? 'Unknown Account';
    final handle =
        (_lookedUpAccount?['username'] as String?) ??
        (_lookedUpAccount?['userId'] as String?) ??
        (_lookedUpAccount?['id'] as String?) ??
        '';
    final avatarUrl = _lookedUpAccount?['avatarUrl'] as String?;
    final canContinue =
        !_isLoading &&
        (_isAgeVerified || (_selectedDate != null && _isOver13()));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Found you?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBase,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.cardBorderColor),
          ),
          child: Column(
            children: [
              AvatarCircle(
                imageUrl: avatarUrl,
                size: 80,
                color: accentColor,
              ),
              const SizedBox(height: 12),
              Text(
                displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (handle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@$handle',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!_isAgeVerified) ...[
          const SizedBox(height: 16),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            onTap: _isLoading ? null : _showDatePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBase,
                border: Border.all(color: AppTheme.buttonBorderColor),
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: AppTheme.secondaryTextColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedDate != null
                          ? '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}'
                          : 'Date of Birth (13+)',
                      style: TextStyle(
                        color:
                            _selectedDate != null
                                ? Colors.white
                                : AppTheme.secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_selectedDate != null)
                    Icon(
                      _isOver13()
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color:
                          _isOver13()
                              ? AppTheme.successColor
                              : AppTheme.errorTextColor,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.tint(AppTheme.errorColor, 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.errorColor.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              _errorMessage.split('\n').first,
              style: const TextStyle(
                color: AppTheme.errorTextColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: TintedButton.neutral(
                onPressed:
                    _isLoading
                        ? null
                        : () {
                          setState(() {
                            _manualVerificationStep = 0;
                            _lookedUpAccount = null;
                            _errorMessage = '';
                          });
                        },
                label: 'Not me',
                height: 48,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TintedButton(
                onPressed: canContinue ? _startManualVerification : null,
                label: widget.isLinkMode ? 'Yes, Link' : 'Yes, Sign In',
                color: accentColor,
                height: 48,
                loading: _isLoading,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildManualVerifyStep(bool isResonite, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Verify Identity',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isResonite
              ? 'Send a message containing the code below to the GalleVR bot in Resonite.'
              : 'Change your VRChat status to the code below so the system knows it\'s really you.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.secondaryTextColor,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        _buildCopyBox(value: _verificationToken),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              isResonite
                  ? 'Waiting for message...'
                  : 'Waiting for status update...',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.bodyTextColor,
              ),
            ),
          ],
        ),
        if (_friendCheckDone && !_isFriend) ...[
          const SizedBox(height: 14),
          Text(
            isResonite
                ? 'Add GalleVR as a friend in Resonite if you aren\'t friends yet.'
                : 'Accept the friend request from GalleVR in VRChat if you aren\'t friends yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildManualSuccessStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_rounded,
            size: 44,
            color: AppTheme.successColor,
          ),
          const SizedBox(height: 14),
          Text(
            widget.isLinkMode ? 'Account Linked!' : 'Success!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.isLinkMode
                ? 'Your accounts are now linked.'
                : 'You are signed in.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyBox({required String value}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                fontSize: 20,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              hoverColor: AppTheme.buttonHoverColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                _copiedResetTimer?.cancel();
                setState(() => _tokenCopied = true);
                _copiedResetTimer = Timer(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() => _tokenCopied = false);
                  }
                });
              },
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  _tokenCopied
                      ? Icons.check_rounded
                      : Icons.content_copy_rounded,
                  size: 18,
                  color:
                      _tokenCopied
                          ? AppTheme.successColor
                          : AppTheme.secondaryTextColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedView() {
    final displayName =
        _lookedUpAccount?['displayName'] ??
        _vrchatService.currentUser?.displayName ??
        _authData?.displayName ??
        'User';

    final avatarUrl = _lookedUpAccount?['avatarUrl'] ?? _authData?.avatarUrl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;

        final avatarWidget = AvatarCircle(
          imageUrl: avatarUrl,
          size: isWide ? 100 : 76,
          color: AppTheme.successColor,
          fallbackIcon: Icons.verified_user_rounded,
        );

        final nameAndStatus = Column(
          crossAxisAlignment:
              isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(
              displayName,
              textAlign: isWide ? TextAlign.left : TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isWide ? 24 : 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
        );

        final actions = Column(
          crossAxisAlignment:
              isWide ? CrossAxisAlignment.end : CrossAxisAlignment.center,
          children: [
            _buildModernButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
                );
              },
              icon: Icons.dashboard_customize_rounded,
              label: 'Go to Dashboard',
              color: AppTheme.brandPurple,
            ),
          ],
        );

        final profileBanner = AppCard(
          padding: EdgeInsets.all(isWide ? 28 : 20),
          child:
              isWide
                  ? Row(
                    children: [
                      avatarWidget,
                      const SizedBox(width: 24),
                      Expanded(child: nameAndStatus),
                      actions,
                    ],
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatarWidget,
                      const SizedBox(height: 12),
                      nameAndStatus,
                      const SizedBox(height: 20),
                      actions,
                    ],
                  ),
        );

        final qrCard = AppCard(
          padding: EdgeInsets.all(isWide ? 32 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.brandPurple,
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Mobile Access',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              BlurrableQrCode(
                revealedData: _galleryUrl,
                blurredData:
                    'https://i.redd.it/zch4bwo7q4zb1.gif', // secret message for sillies who try to unblur someone's QR code >:3
                initiallyRevealed: false,
                onVisibilityChanged: (_) {},
                size: 200,
              ),
            ],
          ),
        );

        final isTwoColumn = constraints.maxWidth >= 900;
        final horizontalPad =
            isWide
                ? ((constraints.maxWidth - 1200) / 2).clamp(
                  28.0,
                  double.infinity,
                )
                : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: isWide ? 24 : 16,
          ),
          child:
              isTwoColumn
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: profileBanner),
                      const SizedBox(width: 24),
                      SizedBox(width: 340, child: qrCard),
                    ],
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [profileBanner, const SizedBox(height: 24), qrCard],
                  ),
        );
      },
    );
  }

  Widget _buildModernButton({
    required VoidCallback? onPressed,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return TintedButton(
      onPressed: onPressed,
      label: label,
      color: color,
      icon: icon,
    );
  }
}
