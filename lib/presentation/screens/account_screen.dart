import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/verification_models.dart';
import '../../data/services/vrchat_service.dart';
import '../widgets/blurrable_qr_code.dart';
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
  bool _isQrCodeVisible = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    super.dispose();
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
      if (mounted) {  // Check if still mounted before calling setState
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
        if (mounted) {  // Check if still mounted
          setState(() {
            _isVerified = true;
            _authData = authData;
            _galleryUrl = 'https://vr.blueberry.coffee/?auth=${authData.accessKey}';
          });
        }
      } else {
        if (mounted) {  // Check if still mounted
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
      builder: (context) => AlertDialog(
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
      // Clear VRChat login if logged in
      if (_vrchatService.isLoggedIn) {
        await _vrchatService.logout();
      }

      // Clear verification data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gallevr_auth_data');

      setState(() {
        _isVerified = false;
        _isQrCodeVisible = false;
        _authData = null;
        _galleryUrl = '';
      });
    } catch (e) {
      developer.log('Error logging out: $e', name: 'AccountScreen');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _isVerified
                  ? _buildVerifiedView()
                  : _buildAccountStatusView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountStatusView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VRChat Account',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const ListTile(
          leading: CircleAvatar(
            child: Icon(Icons.person),
          ),
          title: Text('Not Verified'),
          subtitle: Text('Verify your VRChat account to enable photo sharing'),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: () async {
              // Check if already verified
              final authData = await _vrchatService.loadAuthData();
              if (authData != null) {
                final isVerified = await _vrchatService.checkVerificationStatus(authData);
                if (isVerified) {
                  if (mounted) {
                    // Refresh the screen to show verified status
                    setState(() {
                      _isVerified = true;
                      _authData = authData;
                      _galleryUrl = 'https://vr.blueberry.coffee/?auth=${authData.accessKey}';
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Your account is already verified!'),
                      ),
                    );
                  }
                  return;
                }
              }

              // Navigate to verification screen
              if (mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const VerificationScreen(),
                  ),
                );

                // Refresh the screen after returning from verification
                if (mounted) {
                  await _checkLoginStatus();
                }
              }
            },
            icon: const Icon(Icons.verified_user),
            label: const Text('Verify VRChat Account'),
          ),
        ),
      ],
    );
  }

  Future<void> _launchGallery() async {
    if (_galleryUrl.isNotEmpty && _authData != null) {
      final uri = Uri.parse('https://vr.blueberry.coffee/?auth=${_authData!.accessKey}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open gallery')),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication data is missing')),
      );
    }
  }

  Widget _buildVerifiedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VRChat Account Verified',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.verified_user, color: Colors.white),
          ),
          title: Text('Your account is verified'),
          subtitle: Text('You can now use GalleVR to view and share your photos'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Open GalleVR in your browser:',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Center(
          child: ElevatedButton.icon(
            onPressed: _launchGallery,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open Gallery'),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Or use a QR code:',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'The QR code contains your authentication token. Click "Reveal QR Code" to show it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: BlurrableQrCode(
            revealedData: _galleryUrl,
            blurredData: 'https://i.redd.it/zch4bwo7q4zb1.gif', // secret message for sillies who try to unblur someone's QR code >:3
            initiallyRevealed: _isQrCodeVisible,
            onVisibilityChanged: (isRevealed) {
              setState(() {
                _isQrCodeVisible = isRevealed;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _showLogoutConfirmation,
              child: const Text('Log out'),
            ),
          ],
        ),
      ],
    );
  }


}




