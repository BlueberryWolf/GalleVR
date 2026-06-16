import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/models/config_model.dart';
import '../../data/repositories/config_repository.dart';
import '../widgets/blurrable_qr_code.dart';
import '../widgets/app_card.dart';
import 'verification_screen.dart';

// Screen for VRChat account management
class AccountScreen extends StatefulWidget {
  // Default constructor
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final VRChatService _vrchatService = VRChatService();
  final ConfigRepository _configRepository = ConfigRepository();

  bool _isLoading = true;
  bool _isVerified = false;
  String _galleryUrl = '';
  AuthData? _authData;
  AuthData? _authDataSec;
  ConfigModel? _config;
  bool _isQrCodeVisible = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize VRChat service
      await _vrchatService.initialize();

      // Load config
      _config = await _configRepository.loadConfig();

      // Check if already verified
      await _checkLoginStatus();
    } catch (e) {
      developer.log('Error loading config: $e', name: 'AccountScreen');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkLoginStatus() async {
    final authData = await _vrchatService.loadAuthData();
    final authDataSec = await _vrchatService.loadAuthDataSecondary();

    AuthData? verifiedPrimary;
    AuthData? verifiedSecondary;

    if (authData != null) {
      try {
        final isVerified = await _vrchatService.checkVerificationStatus(
          authData,
        );
        if (isVerified) {
          verifiedPrimary = await _vrchatService.fetchMe(authData) ?? authData;
        }
      } catch (e) {
        verifiedPrimary = authData;
      }
    }

    if (authDataSec != null) {
      try {
        final isVerified = await _vrchatService.checkVerificationStatus(
          authDataSec,
        );
        if (isVerified) {
          verifiedSecondary =
              await _vrchatService.fetchMe(authDataSec) ?? authDataSec;
        }
      } catch (e) {
        verifiedSecondary = authDataSec;
      }
    }

    if (mounted) {
      setState(() {
        _authData = verifiedPrimary;
        _authDataSec = verifiedSecondary;

        final isAndroid = Platform.isAndroid;
        final hasPrimary =
            _authData != null &&
            (!isAndroid || !_authData!.userId.startsWith('U-'));
        final hasSecondary =
            _authDataSec != null &&
            (!isAndroid || !_authDataSec!.userId.startsWith('U-'));
        _isVerified = hasPrimary || hasSecondary;

        final activeAuth =
            hasPrimary ? _authData : (hasSecondary ? _authDataSec : null);
        if (activeAuth != null) {
          _galleryUrl = 'https://gallevr.app/?auth=${activeAuth.accessKey}';
        } else {
          _galleryUrl = '';
        }
      });
    }
  }

  Future<void> _showLogoutConfirmationFor(
    bool isSecondary,
    String accountName,
  ) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Confirm Logout - $accountName'),
            content: const Text(
              'Are you sure you want to log out of this account? You will need to verify it again to access its features.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
    );

    if (shouldLogout == true) {
      await _logoutAccount(isSecondary);
    }
  }

  Future<void> _logoutAccount(bool isSecondary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isSecondary) {
        await prefs.remove('gallevr_auth_data_secondary');
      } else {
        final secondaryJson = prefs.getString('gallevr_auth_data_secondary');
        await prefs.remove('gallevr_auth_data');
        if (secondaryJson != null) {
          await prefs.setString('gallevr_auth_data', secondaryJson);
          await prefs.remove('gallevr_auth_data_secondary');
        } else {
          await _vrchatService.logout();
        }
      }
      await _loadConfig();
    } catch (e) {
      developer.log('Error logging out: $e', name: 'AccountScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: _isVerified ? _buildVerifiedView() : _buildUnverifiedView(),
    );
  }

  Widget _buildUnverifiedView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: AppCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3b82f6), Color(0xFF8b5cf6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Social Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'NOT VERIFIED',
                style: TextStyle(
                  color: Color(0xFFf87171),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify your account to unlock your personal gallery and enable photo sharing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _buildActionButton(
                onPressed: () async {
                  if (mounted) {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const VerificationScreen(),
                      ),
                    );
                    if (mounted) await _checkLoginStatus();
                  }
                },
                icon: Icons.verified_user_rounded,
                label: 'Start Verification',
                color: const Color(0xFF3b82f6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(AuthData auth, bool isSecondary, bool isWide) {
    final displayName = auth.displayName ?? 'User';
    final isResonite = auth.userId.startsWith('U-');
    final platformColor =
        isResonite ? const Color(0xFF00b4d8) : const Color(0xFF8b5cf6);
    final platformText = isResonite ? 'Resonite' : 'VRChat';

    final avatarWidget = Container(
      width: isWide ? 100 : 70,
      height: isWide ? 100 : 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: platformColor.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: platformColor.withOpacity(0.3), width: 2),
      ),
      child:
          auth.avatarUrl != null
              ? Image.network(
                auth.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person_rounded,
                    size: isWide ? 50 : 40,
                    color: platformColor,
                  );
                },
              )
              : Icon(
                Icons.person_rounded,
                size: isWide ? 50 : 40,
                color: platformColor,
              ),
    );

    final nameAndStatus = Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayName,
              style: TextStyle(
                color: Colors.white,
                fontSize: isWide ? 22 : 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: platformColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: platformColor.withOpacity(0.5)),
              ),
              child: Text(
                platformText.toUpperCase(),
                style: TextStyle(
                  color: platformColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final actions = Column(
      crossAxisAlignment:
          isWide ? CrossAxisAlignment.end : CrossAxisAlignment.center,
      children: [
        _buildActionButton(
          onPressed: () => _launchAccountGallery(auth),
          icon: Icons.open_in_new_rounded,
          label: 'Open Gallery',
          color: platformColor,
          width: isWide ? 180 : null,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _showLogoutConfirmationFor(isSecondary, displayName),
          icon: const Icon(Icons.logout_rounded, size: 14),
          label: const Text(
            'LOGOUT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFf87171).withOpacity(0.6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );

    return AppCard(
      padding: EdgeInsets.all(isWide ? 24 : 16),
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
                  const SizedBox(height: 16),
                  actions,
                ],
              ),
    );
  }

  Future<void> _launchAccountGallery(AuthData auth) async {
    final url = Uri.parse('https://gallevr.app/?auth=${auth.accessKey}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log(
        'Error launching account gallery: $e',
        name: 'AccountScreen',
      );
    }
  }

  Widget _buildVerifiedView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final list = <Widget>[];
        final isAndroid = Platform.isAndroid;

        // Primary account
        if (_authData != null) {
          final isRes = _authData!.userId.startsWith('U-');
          if (!isAndroid || !isRes) {
            list.add(_buildProfileCard(_authData!, false, isWide));
          }
        }

        // Secondary account
        if (_authDataSec != null) {
          final isRes = _authDataSec!.userId.startsWith('U-');
          if (!isAndroid || !isRes) {
            if (list.isNotEmpty) list.add(const SizedBox(height: 16));
            list.add(_buildProfileCard(_authDataSec!, true, isWide));
          }
        }

        // Link button
        final hasVRC =
            (_authData != null && !_authData!.userId.startsWith('U-')) ||
            (_authDataSec != null && !_authDataSec!.userId.startsWith('U-'));
        final hasResonite =
            (_authData != null && _authData!.userId.startsWith('U-')) ||
            (_authDataSec != null && _authDataSec!.userId.startsWith('U-'));

        final bool canLink = isAndroid ? !hasVRC : (!hasVRC || !hasResonite);
        if (canLink) {
          final targetPlatform = (isAndroid || !hasVRC) ? 'vrchat' : 'resonite';
          final label =
              targetPlatform == 'vrchat'
                  ? 'Link VRChat Account'
                  : 'Link Resonite Account';
          final btnColor =
              targetPlatform == 'vrchat'
                  ? const Color(0xFF8b5cf6)
                  : const Color(0xFF00b4d8);

          list.add(const SizedBox(height: 24));
          list.add(
            Center(
              child: _buildActionButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (context) => VerificationScreen(
                            initialPlatform: targetPlatform,
                            isLinkMode: true,
                          ),
                    ),
                  );
                  await _loadConfig();
                },
                icon: Icons.add_circle_outline,
                label: label,
                color: btnColor,
              ),
            ),
          );
        }

        // QR code card
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
                children: [...list, const SizedBox(height: 24), qrCard],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    bool outlined = false,
    double? width,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(outlined ? 0.3 : 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: width != null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchGallery() async {
    final url = Uri.parse(_galleryUrl);
    try {
      bool launched = false;
      if (await canLaunchUrl(url)) {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!launched) {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open gallery link')),
        );
      }
    } catch (e) {
      developer.log(
        'Error launching gallery url: $e',
        name: 'AccountScreen',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gallery link: $e')),
        );
      }
    }
  }
}
