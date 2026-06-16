import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gallevr/presentation/screens/home_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/services/tos_service.dart';
import '../theme/app_theme.dart';
import '../widgets/blurrable_qr_code.dart';
import '../widgets/app_card.dart';
import '../widgets/step_indicator.dart';
import '../widgets/tos_modal.dart';
import 'onboarding_screen.dart';

// Screen for VRChat verification
class VerificationScreen extends StatefulWidget {
  final String? initialPlatform;
  final bool isLinkMode;

  const VerificationScreen({super.key, this.initialPlatform, this.isLinkMode = false});

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
    _usernameController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    _pairCodeController.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      await _vrchatService.initialize();

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
          } else if (secondaryAuth != null && secondaryAuth.userId.startsWith('U-')) {
            authData = secondaryAuth;
          }
        } else {
          if (primaryAuth != null && !primaryAuth.userId.startsWith('U-')) {
            authData = primaryAuth;
          } else if (secondaryAuth != null && !secondaryAuth.userId.startsWith('U-')) {
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

        // Check if the user is fully verified (has valid verification)
        final isVerified = await _vrchatService.checkVerificationStatus(
          authData,
        );

        if (isVerified) {
          setState(() {
            _isVerified = true;
            _authData = authData;
            _galleryUrl = 'https://gallevr.app/?auth=${authData!.accessKey}';
          });

          // Check if user needs to accept TOS if they're already verified
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
        setState(() {
          _showTotpField = true;
          _errorMessage = 'Please enter your 2FA code';
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
      final authData = await _vrchatService.pairWithCode(code);

      if (authData != null) {
        await _markAsVerified(authData);
      } else {
        setState(() {
          _errorMessage = 'Invalid or expired pairing code. Please check and try again.';
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
      final fetched = await _vrchatService.fetchMe(baseAuth);
      if (fetched != null) {
        finalAuth = fetched;
      }
    } catch (e) {
      developer.log(
        'Failed to fetch identity detail post-verifying: $e',
        name: 'VerificationScreen',
      );
    }

    if (widget.isLinkMode) {
      await _vrchatService.saveAuthDataSecondary(finalAuth);
    } else {
      await _vrchatService.saveAuthData(finalAuth);
    }
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
    final isResonite = _activePlatform == 'resonite';
    if (_manualVerificationStep == 0) {
      if (_usernameController.text.isEmpty) {
        setState(() {
          _errorMessage = isResonite
              ? 'Please enter your Resonite username'
              : 'Please enter your VRChat username';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _statusMessage = 'Starting verification...';
      });

      try {
        final lookupId = _lookedUpAccount?['id'] ?? _usernameController.text;
        final verificationResult = await _vrchatService.startManualVerification(
          lookupId,
          ageVerified: _isAgeVerified,
        );

        if (verificationResult.success && verificationResult.authData != null) {
          if (widget.isLinkMode) {
            await _vrchatService.saveAuthDataSecondary(verificationResult.authData!);
          } else {
            await _vrchatService.saveAuthData(verificationResult.authData!);
          }

          setState(() {
            _manualVerificationStep = 1;
            _authData = verificationResult.authData;
            _verificationToken = verificationResult.verificationToken ?? '';
          });
        } else {
          setState(() {
            _errorMessage =
                verificationResult.errorMessage ?? 'Verification failed';
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
    } else if (_manualVerificationStep == 1) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _statusMessage = 'Checking friend status...';
      });

      try {
        String lookupId = _lookedUpAccount?['id'] ?? _usernameController.text;
        if (isResonite && !lookupId.startsWith('U-')) {
          lookupId = 'U-$lookupId';
        }
        final isFriend = await _vrchatService.checkFriendStatus(lookupId);

        if (isFriend) {
          setState(() {
            _manualVerificationStep = 2;
            _statusMessage = 'Friend status confirmed!';
          });
        } else {
          setState(() {
            _errorMessage = isResonite
                ? 'Friend request not found. Please add GalleVR as a friend in Resonite and try again.'
                : 'Friend request not found. Please add GalleVR as a friend in VRChat and try again.';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Error checking friend status: $e';
        });
      } finally {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    } else if (_manualVerificationStep == 2) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _statusMessage = 'Checking verification status...';
      });

      try {
        if (_authData != null) {
          final isVerified = await _vrchatService.checkVerificationStatus(
            _authData!,
          );

          if (isVerified) {
            await _markAsVerified(_authData!);
          } else {
            await Future.delayed(const Duration(seconds: 3));
            final retryVerified = await _vrchatService.checkVerificationStatus(
              _authData!,
            );

            if (retryVerified) {
              await _markAsVerified(_authData!);
            } else {
              setState(() {
                _errorMessage = isResonite
                    ? 'Verification failed. Please make sure you\'ve sent the verification token to the Resonite bot and try again.'
                    : 'Verification failed. Please make sure you\'ve set your VRChat status to the verification token and try again.';
              });
            }
          }
        } else {
          setState(() {
            _errorMessage =
                'Authentication data is missing. Please restart the verification process.';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Error checking verification status: $e';
        });
      } finally {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _performAccountLookup() async {
    final text = _usernameController.text.trim();
    if (text.length < 2) return;

    setState(() {
      _isLookingUp = true;
      _errorMessage = '';
      _lookedUpAccount = null;
    });

    try {
      final platform = _activePlatform ?? 'vrchat';
      final account = await _vrchatService.lookupAccount(text, platform: platform);
      setState(() {
        _lookedUpAccount = account;
        if (account == null) {
          _errorMessage = platform == 'resonite'
              ? 'No matching Resonite account found on API.'
              : 'No matching VRChat account found on API.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Search request error.';
      });
    } finally {
      setState(() {
        _isLookingUp = false;
      });
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
        // Only check if over 13, but don't set _isAgeVerified yet
        // We'll set it when the user clicks the verify button
        if (!_isOver13()) {
          _errorMessage = 'You must be at least 13 years old to use this app.';
        } else {
          _errorMessage = '';
        }
      });
    }
  }

  /// Check if the user needs to accept the TOS
  Future<void> _checkTOSStatus() async {
    try {
      // Check if user needs to accept TOS
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

  /// Handle TOS acceptance
  void _handleTOSAccept() {
    setState(() {
      _showTOSModal = false;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Terms of Service accepted. You can now use the app.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Handle TOS decline
  void _handleTOSDecline() {
    setState(() {
      _showTOSModal = false;
    });

    // Show warning message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can still use the app, but some features may be limited.',
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_activePlatform == null
            ? 'Link Account'
            : _activePlatform == 'resonite'
                ? 'Resonite Verification'
                : 'VRChat Verification'),
        backgroundColor: AppTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_activePlatform == 'resonite' && _selectedMethod != null) {
              setState(() {
                _selectedMethod = null;
                _activePlatform = widget.initialPlatform == null ? null : _activePlatform;
                _errorMessage = '';
              });
            } else if (_selectedMethod != null) {
              setState(() {
                _selectedMethod = null;
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
                MaterialPageRoute(
                  builder: (context) => const OnboardingScreen(),
                ),
              );
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // Main content
          _isVerified
              ? _buildVerifiedView()
              : Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_activePlatform == null)
                          _buildPlatformPickerView()
                        else if (_selectedMethod == null)
                          _buildMethodSelectionLanding()
                        else if (_selectedMethod ==
                            VerificationMethod.pairCode)
                          _buildPairCodeVerificationView()
                        else if (_selectedMethod ==
                            VerificationMethod.automatic)
                          _buildAutomaticVerificationView()
                        else
                          _buildManualVerificationView(),
                      ],
                    ),
                  ),

                  if (_isLoading)
                    Container(
                      color: Colors.black.withAlpha(76),
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  _statusMessage.isNotEmpty
                                      ? _statusMessage
                                      : 'Processing...',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

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

  Widget _buildPlatformPickerView() {
    return Padding(
      padding: const EdgeInsets.only(
        top: 32.0,
        bottom: 24.0,
        left: 12.0,
        right: 12.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Primary Platform',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 4,
            width: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Pick the account you want to link to GalleVR or enter a website pairing code.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 36),

          _buildGradientActionCard(
            title: 'Instant Link Code',
            description: 'Best option. If you followed onboarding on the website, just type the 6-digit code here.',
            icon: Icons.flash_on_rounded,
            gradientColors: [const Color(0xFF3B82F6), const Color(0xFF06B6D4)],
            onTap: () {
              setState(() {
                _selectedMethod = VerificationMethod.pairCode;
                _activePlatform = 'vrchat'; // Default state to proceed
                _errorMessage = '';
              });
            },
          ),
          const SizedBox(height: 20),

          _buildGradientActionCard(
            title: 'VRChat',
            description: 'Link your VRChat account to organize and share your VRChat photos.',
            imageAsset: 'assets/images/VRChat_logo.png',
            gradientColors: [const Color(0xFF8B5CF6), const Color(0xFF4C1D95)],
            onTap: () {
              setState(() {
                _activePlatform = 'vrchat';
                _errorMessage = '';
              });
            },
          ),
          const SizedBox(height: 20),

          _buildGradientActionCard(
            title: 'Resonite',
            description: 'Link your Resonite account using our verification bot.',
            imageAsset: 'assets/images/resonite_logo.png',
            gradientColors: [const Color(0xFF00B4D8), const Color(0xFF0077B6)],
            onTap: () {
              setState(() {
                _activePlatform = 'resonite';
                _selectedMethod = VerificationMethod.manual;
                _errorMessage = '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSelectionLanding() {
    return Padding(
      padding: const EdgeInsets.only(
        top: 32.0,
        bottom: 24.0,
        left: 12.0,
        right: 12.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link VRChat',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 4,
            width: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'To link your VRChat account, I just need to confirm you own it. You verify with a temporary code in your VRChat status.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 48),

          _buildGradientActionCard(
            title: 'Automatic Verification',
            description:
                'Log in once and GalleVR will automatically handle adding and removing the verification code from your status for you.',
            icon: Icons.verified_user_rounded,
            gradientColors: [const Color(0xFF8B5CF6), const Color(0xFF4C1D95)],
            onTap: () {
              setState(() {
                _selectedMethod = VerificationMethod.automatic;
                _errorMessage = '';
              });
            },
          ),
          const SizedBox(height: 20),
          _buildGradientActionCard(
            title: 'Manual Verification',
            description:
                'Prefer to handle it yourself? Just look up your account and copy the code in manually.',
            icon: Icons.edit_note_rounded,
            gradientColors: [const Color(0xFFEC4899), const Color(0xFF7C3AED)],
            onTap: () {
              setState(() {
                _selectedMethod = VerificationMethod.manual;
                _errorMessage = '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPairCodeVerificationView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Instant Pair Code',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Look at the website setup screen. You\'ll find a 6-digit numerical code there.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[400],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                border: Border.all(color: Colors.red.withAlpha(80)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.redAccent),
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
              fontWeight: FontWeight.bold,
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
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitPairCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Pair Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _selectedMethod = null;
                  _errorMessage = '';
                });
              },
              child: Text(
                'Go Back',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientActionCard({
    required String title,
    required String description,
    IconData? icon,
    String? imageAsset,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withAlpha(50),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF141417),
            border: Border.all(
              color: gradientColors.first.withAlpha(80),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors.map((c) => c.withAlpha(35)).toList(),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    shape: BoxShape.circle,
                  ),
                  child: imageAsset != null
                      ? imageAsset.endsWith('.svg')
                          ? Icon(Icons.hub_rounded, size: 28, color: Colors.white) // Native flutter SVG packages aren't imported here, fallback to nice icon for safety
                          : Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Image.asset(imageAsset, fit: BoxFit.contain),
                            )
                      : Icon(icon ?? Icons.flash_on_rounded, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withAlpha(200),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 20,
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
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF8B5CF6),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Automatic Verification',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Sign in to your VRChat account and I\'ll handle the verification process for you.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username or Email',
              prefixIcon: Icon(Icons.person_rounded),
            ),
            enabled: !_isLoading,
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
          ),
          if (!_isAgeVerified) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Age Verification',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You must be at least 13 years old. Please enter your date of birth:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isLoading ? null : _showDatePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: Colors.white70,
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
                                : Colors.white38,
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
                    color: _isOver13() ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOver13() ? 'Age verified' : 'Must be at least 13',
                    style: TextStyle(
                      color: _isOver13() ? Colors.green : Colors.red,
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
              decoration: const InputDecoration(
                labelText: '2FA Code',
                prefixIcon: Icon(Icons.security_rounded),
              ),
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
            ),
          ],
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFf87171).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFf87171).withOpacity(0.3),
                ),
              ),
              child: Text(
                _errorMessage.split('\n').first,
                style: const TextStyle(color: Color(0xFFf87171), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Center(
            child: _buildActionButton(
              onPressed: () {
                if (!_isAgeVerified) {
                  if (_selectedDate == null || !_isOver13()) {
                    setState(() {
                      _errorMessage = 'Please complete age verification first.';
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
              color: const Color(0xFF8B5CF6),
              icon: Icons.login_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualVerificationView() {
    final isResonite = _activePlatform == 'resonite';
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual Verification',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 3,
            width: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(height: 16),
          StepIndicator(
            steps: const ['Start', 'Friendship', 'Verify'],
            currentStep: _manualVerificationStep,
          ),
          const SizedBox(height: 16),
          if (_manualVerificationStep == 0) ...[
            const Text(
              'Enter your display name or user ID to fetch your profile.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Display Name or User ID',
                prefixIcon: const Icon(Icons.person),
                helperText: 'e.g. "DisplayExample" or "usr_XXXX"',
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child:
                      _isLookingUp
                          ? Transform.scale(
                            scale: 0.5,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Color(0xFF8B5CF6),
                            ),
                          )
                          : IconButton(
                            icon: const Icon(
                              Icons.search,
                              color: Color(0xFF8B5CF6),
                            ),
                            onPressed:
                                _isLoading ? null : _performAccountLookup,
                            tooltip: 'Search',
                          ),
                ),
              ),
              enabled: !_isLoading,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performAccountLookup(),
            ),

            if (_lookedUpAccount != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryColor.withAlpha(80),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black45,
                      backgroundImage:
                          _lookedUpAccount!['avatarUrl'] != null
                              ? NetworkImage(_lookedUpAccount!['avatarUrl'])
                              : null,
                      child:
                          _lookedUpAccount!['avatarUrl'] == null
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lookedUpAccount!['displayName'] ??
                                'Unknown Account',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _lookedUpAccount!['userId'] ?? '',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verify this profile is correct before continuing.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],

            // Date of birth input
            if (!_isAgeVerified) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Age Verification',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'You must be at least 13 years old to use this app. Please enter your date of birth:',
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _showDatePicker,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _selectedDate != null
                        ? '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}'
                        : 'Select Date',
                  ),
                ),
              ),
              if (_selectedDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _isOver13() ? Icons.check_circle : Icons.error,
                      color: _isOver13() ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOver13()
                          ? 'Age verified'
                          : 'You must be at least 13 years old',
                      style: TextStyle(
                        color: _isOver13() ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ] else if (_manualVerificationStep == 1) ...[
            Text(isResonite ? 'Add GalleVR as a friend in Resonite:' : 'Add GalleVR as a friend in VRChat:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    isResonite ? 'GalleVR' : 'GalleVR',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: isResonite ? 'GalleVR' : 'GalleVR'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isResonite ? 'Copied "GalleVR" to clipboard' : 'Copied "GalleVR" to clipboard'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    tooltip: 'Copy to clipboard',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(isResonite ? 'Follow these steps in Resonite:' : 'Follow these steps in VRChat:'),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(child: Text('1')),
              title: Text(isResonite ? 'Send a friend request to "GalleVR"' : 'Check your VRChat Notifications'),
              subtitle: Text(
                isResonite ? 'Search for "GalleVR" in Resonite and add them.' : 'A friend request from "GalleVR" should be waiting for you.',
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('2')),
              title: Text(isResonite ? 'Wait for bot to accept friend request' : 'Accept the friend request'),
              subtitle: Text(isResonite ? 'The bot automatically accepts all friend requests within a few seconds.' : 'This allows us to verify your profile status.'),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('3')),
              title: Text(isResonite ? 'Click "Continue" below' : 'Click "Check Status" below'),
              subtitle: Text(isResonite ? 'We\'ll progress to token message verification.' : 'We\'ll confirm once the friendship is active.'),
            ),
            const SizedBox(height: 16),
            if (!isResonite)
              const Text(
                'Tip: If you don\'t see a request, you can also search for "GalleVR" manually and send one to us.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
          ] else if (_manualVerificationStep == 2) ...[
            Text(isResonite ? 'Send the verification token to the Resonite bot:' : 'Set your VRChat status to the verification token:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.token, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _verificationToken,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _verificationToken),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Copied verification token to clipboard',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    tooltip: 'Copy to clipboard',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(isResonite ? 'Follow these steps in Resonite:' : 'Follow these steps in VRChat:'),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(child: Text('1')),
              title: Text(isResonite ? 'Open chat with GalleVR in Resonite' : 'In VRChat, go to your Profile and edit your status'),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('2')),
              title: Text(isResonite ? 'Send the token text exactly as a message' : 'Paste the verification token as your status'),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('3')),
              title: const Text('Click "Verify Status" below'),
            ),
            const SizedBox(height: 16),
            Text(
              isResonite
                  ? 'When you click "Verify Status", we\'ll check if our Resonite bot received your token.'
                  : 'When you click "Verify Status", we\'ll check if your VRChat status contains the verification token.',
            ),
            const SizedBox(height: 16),
            const Text('If verification fails, please make sure:'),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(isResonite ? 'You\'ve added GalleVR as a friend' : 'You\'ve added GalleVR as a friend'),
              dense: true,
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(
                isResonite
                    ? 'You sent the exact token message to the bot'
                    : 'Your status message contains the exact verification token',
              ),
              dense: true,
            ),
            if (!isResonite)
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text(
                  'You\'ve waited a few minutes for VRChat to update your status',
                ),
                dense: true,
              ),
          ],
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage.split('\n').first,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              ElevatedButton(
                onPressed:
                    (_manualVerificationStep == 0 &&
                                !_isAgeVerified &&
                                (_selectedDate == null || !_isOver13()) ||
                            _isLoading)
                        ? null
                        : () {
                          // Only set _isAgeVerified to true if the user is over 13, we're on step 0, and not already verified
                          if (_manualVerificationStep == 0 &&
                              !_isAgeVerified &&
                              _selectedDate != null &&
                              _isOver13()) {
                            setState(() {
                              _isAgeVerified = true;
                            });
                          }
                          _startManualVerification();
                        },
                child: Text(() {
                  switch (_manualVerificationStep) {
                    case 0:
                      return 'Continue';
                    case 1:
                      return 'Check Friend Status';
                    case 2:
                      return 'Verify Status';
                    default:
                      return 'Continue';
                  }
                }()),
              ),
            ],
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

    final avatarUrl =
        _lookedUpAccount?['avatarUrl'] ??
        _authData?.avatarUrl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;

        final avatarWidget = Container(
          width: isWide ? 120 : 80,
          height: isWide ? 120 : 80,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF4ade80).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF4ade80).withOpacity(0.3),
              width: 2,
            ),
          ),
          child:
              avatarUrl != null
                  ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.verified_user_rounded,
                        size: isWide ? 60 : 50,
                        color: const Color(0xFF4ade80),
                      );
                    },
                  )
                  : Icon(
                    Icons.verified_user_rounded,
                    size: isWide ? 60 : 50,
                    color: const Color(0xFF4ade80),
                  ),
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
                fontSize: isWide ? 28 : 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
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
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              },
              icon: Icons.dashboard_customize_rounded,
              label: 'Go to Dashboard',
              color: const Color(0xFF3b82f6),
            ),
          ],
        );

        final profileBanner = AppCard(
          padding: EdgeInsets.all(isWide ? 40 : 20),
          child:
              isWide
                  ? Row(
                    children: [
                      avatarWidget,
                      const SizedBox(width: 32),
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
          padding: EdgeInsets.all(isWide ? 40 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mobile Access',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan to view your gallery on your phone',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
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

        return SingleChildScrollView(
          padding: EdgeInsets.all(isWide ? 40 : 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [profileBanner, const SizedBox(height: 24), qrCard],
              ),
            ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: onPressed == null ? Colors.white24 : color,
              ),
              const SizedBox(width: 12),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: onPressed == null ? Colors.white24 : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
