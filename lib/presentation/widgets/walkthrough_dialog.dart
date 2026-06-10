import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class WalkthroughDialog extends StatefulWidget {
  final VoidCallback onDismissed;

  const WalkthroughDialog({super.key, required this.onDismissed});

  static Future<void> showIfRequired(
    BuildContext context, {
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isShown = prefs.getBool('walkthrough_shown') ?? false;

    if (!isShown || force) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => WalkthroughDialog(
                onDismissed: () async {
                  await prefs.setBool('walkthrough_shown', true);
                },
              ),
        );
      }
    }
  }

  @override
  State<WalkthroughDialog> createState() => _WalkthroughDialogState();
}

class _WalkthroughDialogState extends State<WalkthroughDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_SlideData> _slides = [
    _SlideData(
      icon: Icons.favorite_rounded,
      iconColor: const Color(0xFF8B5CF6),
      title: 'Welcome to GalleVR',
      content:
          'GalleVR is my passion project, built by a solo developer. There may be a few issues here and there, but I hope you love it!\n\n'
          'Please note: most of GalleVR\'s features (galleries, feed, social features) live on the GalleVR website. This app is a companion to the website that tags your photos locally and uploads them.',
    ),
    _SlideData(
      icon: Icons.settings_suggest_rounded,
      iconColor: const Color(0xFF22D3EE),
      title: 'Keep it Running',
      content:
          'Photos can only be uploaded if GalleVR was open when they were taken, or if you had the third-party app VRCX tagging them.\n\n'
          'I highly advise letting GalleVR start with Windows and run minimized to tray. I optimized it to use 0% CPU, 0% GPU, and only ~7-8MB of RAM when minimized, so it will not impact your performance!',
    ),
    _SlideData(
      icon: Icons.image_search_rounded,
      iconColor: const Color(0xFF3B82F6),
      title: 'How Photos Appear',
      content:
          'To show up in the Photos tab, a screenshot needs embedded world and player metadata.\n\n'
          'VRChat\'s default photo capture now has limited support (allowing uploads with just world info). Otherwise, if a photo was taken while GalleVR (or VRCX with metadata enabled) was running, it will be tagged with full metadata and appear in the tab.',
    ),
    _SlideData(
      icon: Icons.cloud_upload_rounded,
      iconColor: Colors.grey,
      title: 'Grey vs. Uploaded Photos',
      content:
          'The Photos tab displays all eligible photos. If a photo is grey, it means it has metadata but has not been uploaded to the GalleVR website yet. Simply click on any grey photo and select Upload Photo to upload it!\n\n'
          'Older VRChat screenshots and VRCX photos with metadata enabled will also show up as grey and can be retroactively uploaded.',
    ),
    _SlideData(
      icon: Icons.collections_bookmark_rounded,
      iconColor: const Color(0xFF4ADE80),
      title: 'Organize with Galleries',
      content:
          'On the website, you can organize your photos using Galleries.\n\n'
          'Use manual galleries to place photos inside manually, or automatic galleries to let GalleVR auto-organize photos dynamically using the metadata we tagged.',
    ),
    _SlideData(
      icon: Icons.campaign_rounded,
      iconColor: const Color(0xFFF472B6),
      title: 'Share to the Feed',
      content:
          'When photos are uploaded, they are private by default, meaning only you can see them.\n\n'
          'To share, find the photo on the website, click it to open the viewer, click the three dots in the bottom right, and select Feed to post it so other users can find it, like it, and share it!',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    widget.onDismissed();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;

    return Stack(
      children: [
        // Backdrop Blur overlay
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),
        ),

        // Dialog Panel
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: isSmallScreen ? size.width * 0.9 : 520,
              height: 480,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.cardBorderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // PageView for slides
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                      },
                      itemCount: _slides.length,
                      itemBuilder: (context, index) {
                        return _buildSlide(_slides[index]);
                      },
                    ),
                  ),

                  // Bottom Action bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: AppTheme.cardBorderColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Skip Button
                        TextButton(
                          onPressed: _finish,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        // Progress Indicator
                        Row(
                          children: List.generate(
                            _slides.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 6,
                              width: _currentPage == index ? 16 : 6,
                              decoration: BoxDecoration(
                                color:
                                    _currentPage == index
                                        ? AppTheme.primaryColor
                                        : Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),

                        // Next/Finish Button
                        ElevatedButton(
                          onPressed: _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            _currentPage == _slides.length - 1
                                ? 'Finish'
                                : 'Next',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlide(_SlideData slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: slide.iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: slide.iconColor.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Icon(slide.icon, size: 40, color: slide.iconColor),
          ),
          const SizedBox(height: 24),

          // Slide Title
          Text(
            slide.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Slide Content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                slide.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String content;

  _SlideData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.content,
  });
}
