import 'dart:developer' as developer;
import 'dart:io' show Platform, Process;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../../data/services/app_service_manager.dart';
import '../widgets/blurrable_qr_code.dart';
import '../widgets/app_card.dart';
import '../widgets/tinted_button.dart';
import 'verification_screen.dart';
import '../theme/app_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final VRChatService _vrchatService = VRChatService();

  bool _isLoading = true;
  bool _isVerified = false;
  String _galleryUrl = '';
  AuthData? _authData;
  AuthData? _authDataSec;

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
      await _vrchatService.initialize();

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
      await AppServiceManager().refreshAuth();
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
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.tint(AppTheme.primaryColor, 0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 32,
                  color: AppTheme.primaryLightColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Social Account',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Not verified',
                style: TextStyle(
                  color: AppTheme.errorColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify your account to unlock your personal gallery and enable photo sharing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.secondaryTextColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TintedButton(
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
                color: AppTheme.primaryColor,
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

    final avatarSize = isWide ? 100.0 : 70.0;
    final avatarFallback = Center(
      child: Icon(
        Icons.person_rounded,
        size: avatarSize / 2,
        color: platformColor,
      ),
    );
    final avatarWidget = Container(
      width: avatarSize,
      height: avatarSize,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: platformColor.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppTheme.tint(platformColor, 0.15),
          child:
              auth.avatarUrl != null
                  ? Image.network(
                    auth.avatarUrl!,
                    width: avatarSize,
                    height: avatarSize,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => avatarFallback,
                  )
                  : avatarFallback,
        ),
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
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.tint(platformColor, 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusTag),
              ),
              child: Text(
                platformText,
                style: TextStyle(
                  color: platformColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
        TintedButton(
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
          label: const Text('Log out'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
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
      bool launched = false;
      if (await canLaunchUrl(url)) {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!launched && Platform.isLinux) {
        await Process.run('xdg-open', [url.toString()]);
      }
    } catch (e) {
      developer.log(
        'Error launching account gallery: $e',
        name: 'AccountScreen',
      );
      if (Platform.isLinux) {
        try {
          await Process.run('xdg-open', [url.toString()]);
        } catch (err) {
          developer.log(
            'xdg-open fallback failed: $err',
            name: 'AccountScreen',
          );
        }
      }
    }
  }

  Widget _buildVerifiedView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final list = <Widget>[];
        final isAndroid = Platform.isAndroid;

        if (_authData != null) {
          final isRes = _authData!.userId.startsWith('U-');
          if (!isAndroid || !isRes) {
            list.add(_buildProfileCard(_authData!, false, isWide));
          }
        }

        if (_authDataSec != null) {
          final isRes = _authDataSec!.userId.startsWith('U-');
          if (!isAndroid || !isRes) {
            if (list.isNotEmpty) list.add(const SizedBox(height: 16));
            list.add(_buildProfileCard(_authDataSec!, true, isWide));
          }
        }

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
              child: TintedButton(
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
                      color: AppTheme.tint(AppTheme.primaryColor, 0.15),
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppTheme.primaryLightColor,
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
                          color: AppTheme.secondaryTextColor,
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
}
