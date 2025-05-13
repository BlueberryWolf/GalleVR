import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gallevr/presentation/screens/home_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/blurrable_qr_code.dart';
import '../widgets/step_indicator.dart';

// Screen for VRChat verification
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final VRChatService _vrchatService = VRChatService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _totpController = TextEditingController();

  bool _isLoading = false;
  bool _isVerified = false;
  bool _showTotpField = false;
  bool _showQrCode = false;
  String _errorMessage = '';
  String _statusMessage = '';
  VerificationMethod _selectedMethod = VerificationMethod.automatic;
  int _manualVerificationStep = 0;
  AuthData? _authData;
  String _galleryUrl = '';
  String _verificationToken = '';

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      await _vrchatService.initialize();

      final authData = await _vrchatService.loadAuthData();
      if (authData != null) {
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
            _galleryUrl =
                'https://vr.blueberry.coffee/?auth=${authData.accessKey}';
          });
        }
      }
    } catch (e) {
      developer.log('Error initializing verification service: $e', name: 'VerificationScreen');
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

        final verificationResult =
            await _vrchatService.startAutomaticVerification();

        if (verificationResult.success && verificationResult.authData != null) {
          await _vrchatService.saveAuthData(verificationResult.authData!);

          final isVerified = await _vrchatService.checkVerificationStatus(
            verificationResult.authData!,
          );

          if (isVerified) {
            setState(() {
              _isVerified = true;
              _authData = verificationResult.authData;
              _galleryUrl =
                  'https://vr.blueberry.coffee/?auth=${verificationResult.authData!.accessKey}';
            });
          } else {
            await Future.delayed(const Duration(seconds: 2));
            final retryVerified = await _vrchatService.checkVerificationStatus(
              verificationResult.authData!,
            );

            if (retryVerified) {
              setState(() {
                _isVerified = true;
                _authData = verificationResult.authData;
                _galleryUrl =
                    'https://vr.blueberry.coffee/?auth=${verificationResult.authData!.accessKey}';
              });
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

  Future<void> _startManualVerification() async {
    if (_manualVerificationStep == 0) {
      if (_usernameController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter your VRChat username';
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _statusMessage = 'Starting verification...';
      });

      try {
        final verificationResult = await _vrchatService.startManualVerification(
          _usernameController.text,
        );

        if (verificationResult.success && verificationResult.authData != null) {
          await _vrchatService.saveAuthData(verificationResult.authData!);

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
        final isFriend = await _vrchatService.checkFriendStatus(
          _usernameController.text,
        );

        if (isFriend) {
          setState(() {
            _manualVerificationStep = 2;
            _statusMessage = 'Friend status confirmed!';
          });
        } else {
          setState(() {
            _errorMessage =
                'Friend request not found. Please add GalleVR as a friend in VRChat and try again.';
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
            await _vrchatService.saveAuthData(_authData!);

            setState(() {
              _isVerified = true;
              _galleryUrl =
                  'https://vr.blueberry.coffee/?auth=${_authData!.accessKey}';
            });
          } else {
            await Future.delayed(const Duration(seconds: 3));
            final retryVerified = await _vrchatService.checkVerificationStatus(
              _authData!,
            );

            if (retryVerified) {
              await _vrchatService.saveAuthData(_authData!);

              setState(() {
                _isVerified = true;
                _galleryUrl =
                    'https://vr.blueberry.coffee/?auth=${_authData!.accessKey}';
              });
            } else {
              setState(() {
                _errorMessage =
                    'Verification failed. Please make sure you\'ve set your VRChat status to the verification token and try again.';
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

  Future<void> _launchGallery() async {
    if (_galleryUrl.isNotEmpty) {
      final uri = Uri.parse(_galleryUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        setState(() {
          _errorMessage = 'Could not launch gallery URL';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VRChat Verification'),
        backgroundColor: AppTheme.backgroundColor,
      ),
      body:
          _isVerified
              ? _buildVerifiedView()
              : Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMethodSelector(),
                        const SizedBox(height: 16),
                        _selectedMethod == VerificationMethod.automatic
                            ? _buildAutomaticVerificationView()
                            : _buildManualVerificationView(),
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
    );
  }

  Widget _buildMethodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VRChat Verification',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text('Choose a verification method:'),
            const SizedBox(height: 8),
            SegmentedButton<VerificationMethod>(
              segments: const [
                ButtonSegment<VerificationMethod>(
                  value: VerificationMethod.automatic,
                  label: Text('Automatic'),
                  icon: Icon(Icons.auto_awesome),
                ),
                ButtonSegment<VerificationMethod>(
                  value: VerificationMethod.manual,
                  label: Text('Manual'),
                  icon: Icon(Icons.person_add),
                ),
              ],
              selected: {_selectedMethod},
              onSelectionChanged: (Set<VerificationMethod> selection) {
                setState(() {
                  _selectedMethod = selection.first;
                  _errorMessage = '';
                  _statusMessage = '';
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomaticVerificationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automatic Verification',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Log in with your VRChat account to verify automatically. Your credentials are only used for authentication and are not stored.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username or Email',
                prefixIcon: Icon(Icons.person),
              ),
              enabled: !_isLoading,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              enabled: !_isLoading,
              textInputAction:
                  _showTotpField ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (!_showTotpField) {
                  _login();
                }
              },
            ),
            if (_showTotpField) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _totpController,
                decoration: const InputDecoration(
                  labelText: '2FA Code',
                  prefixIcon: Icon(Icons.security),
                ),
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
            ],
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: const Text('Verify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualVerificationView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Verification',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StepIndicator(
              steps: const ['Enter Username', 'Add Friend', 'Update Status'],
              currentStep: _manualVerificationStep,
            ),
            const SizedBox(height: 16),
            if (_manualVerificationStep == 0) ...[
              const Text(
                'Enter your VRChat username to start the verification process.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'VRChat Username',
                  prefixIcon: Icon(Icons.person),
                  helperText: 'This is the name other users see in VRChat',
                ),
                enabled: !_isLoading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _startManualVerification(),
              ),
            ] else if (_manualVerificationStep == 1) ...[
              const Text('Add GalleVR as a friend in VRChat:'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      'GalleVR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: 'GalleVR'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied "GalleVR" to clipboard'),
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
              const Text('Follow these steps in VRChat:'),
              const SizedBox(height: 8),
              const ListTile(
                leading: CircleAvatar(child: Text('1')),
                title: Text('Open VRChat'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('2')),
                title: Text('Open the menu and go to Social → User Search'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('3')),
                title: Text('Search for "GalleVR" and send a friend request'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('4')),
                title: Text(
                  'Click "Check Status" below once you\'ve sent the request',
                ),
              ),
            ] else if (_manualVerificationStep == 2) ...[
              const Text('Set your VRChat status to the verification token:'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
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
              const Text('Follow these steps in VRChat:'),
              const SizedBox(height: 8),
              const ListTile(
                leading: CircleAvatar(child: Text('1')),
                title: Text('Open VRChat'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('2')),
                title: Text('Open the menu and go to Profile'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('3')),
                title: Text('Click on your status message'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('4')),
                title: Text('Paste the verification token as your status'),
              ),
              const ListTile(
                leading: CircleAvatar(child: Text('5')),
                title: Text(
                  'Click "Verify Status" below once you\'ve set your status',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'When you click "Verify Status", we\'ll check if your VRChat status contains the verification token.',
              ),
              const SizedBox(height: 16),
              const Text('If verification fails, please make sure:'),
              const SizedBox(height: 8),
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('You\'ve added GalleVR as a friend'),
                dense: true,
              ),
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text(
                  'Your status message contains the exact verification token',
                ),
                dense: true,
              ),
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
                _errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                ElevatedButton(
                  onPressed: _isLoading ? null : _startManualVerification,
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
      ),
    );
  }

  Widget _buildVerifiedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Verification Complete!',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You can now use GalleVR to view and share your photos.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Open GalleVR in your browser:',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _launchGallery,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open Gallery'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Or use a QR code:', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'The QR code contains your authentication token. Click "Reveal QR Code" to show it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  BlurrableQrCode(
                    revealedData: _galleryUrl,
                    blurredData: 'https://i.redd.it/zch4bwo7q4zb1.gif', // secret message for sillies who try to unblur someone's QR code >:3
                    initiallyRevealed: _showQrCode,
                    onVisibilityChanged: (isRevealed) {
                      setState(() {
                        _showQrCode = isRevealed;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      const HomeScreen(initialTabIndex: 2),
                            ),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Return to Account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
