import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
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

  bool _isLoading = true;
  bool _isVerified = false;
  String _galleryUrl = '';
  AuthData? _authData;
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
    // Check if there's saved verification data
    final authData = await _vrchatService.loadAuthData();
    if (authData != null) {
      final isVerified = await _vrchatService.checkVerificationStatus(authData);

      if (isVerified) {
        final latestAuthData = await _vrchatService.fetchMe(authData);

        if (mounted) {
          setState(() {
            _isVerified = true;
            _authData = latestAuthData ?? authData;
            _galleryUrl = 'https://gallevr.app/?auth=${_authData!.accessKey}';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isVerified = false;
            _authData = null;
            _galleryUrl = '';
          });
        }
      }
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text(
              'Are you sure you want to log out? You will need to verify your account again to access your gallery.',
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
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      await _vrchatService.logout();

      // Preserve age verification status globally
      bool ageVerified = _authData?.ageVerified ?? false;
      if (ageVerified) {
        await _vrchatService.setAgeVerified(true);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gallevr_auth_data');

      if (mounted) {
        setState(() {
          _isVerified = false;
          _authData = null;
          _galleryUrl = '';
        });
      }
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
                'VRChat Account',
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
                'Verify your VRChat account to unlock your personal gallery and enable photo sharing.',
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

  Widget _buildVerifiedView() {
    final displayName =
        _authData?.displayName ??
        _vrchatService.currentUser?.displayName ??
        'User';

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
              _authData?.avatarUrl != null
                  ? Image.network(
                    _authData!.avatarUrl!,
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
          ],
        );

        final actions = Column(
          crossAxisAlignment:
              isWide ? CrossAxisAlignment.end : CrossAxisAlignment.center,
          children: [
            _buildActionButton(
              onPressed: _launchGallery,
              icon: Icons.open_in_new_rounded,
              label: 'Open Web Gallery',
              color: const Color(0xFF3b82f6),
              width: isWide ? 220 : null,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showLogoutConfirmation,
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text(
                'LOGOUT ACCOUNT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFf87171).withOpacity(0.6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open gallery link')),
        );
      }
    }
  }
}
