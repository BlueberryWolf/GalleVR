import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';
import '../theme/app_theme.dart';
import 'tinted_button.dart';

class UpdateDialog extends StatefulWidget {
  final String latestVersion;

  const UpdateDialog({super.key, required this.latestVersion});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _progress = 0.0;
  String _errorMessage = '';

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = '';
      _progress = 0.0;
    });

    try {
      await _updateService.downloadAndInstall(
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Update failed: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isSmallScreen = size.width < 600;

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withValues(alpha: 0.65)),
            ),
          ),
        ),

        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: isSmallScreen ? size.width * 0.9 : 450,
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.modalDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.system_update_rounded,
                        color: AppTheme.brandPurple,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Update Available',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.cardBorderColor, height: 1),
                  const SizedBox(height: 18),

                  if (!_isDownloading) ...[
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppTheme.bodyTextColor,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(text: 'A new version of GalleVR ('),
                          TextSpan(
                            text: 'v${widget.latestVersion}',
                            style: const TextStyle(
                              color: AppTheme.brandPurple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(
                            text:
                                ') is available. Would you like to download and install it now?',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The application will temporarily close during the installation and reopen automatically when finished.',
                      style: TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ] else ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Downloading update...',
                              style: TextStyle(
                                color: AppTheme.bodyTextColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: AppTheme.brandPurple,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _progress,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.brandPurple,
                            ),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Please do not close the application.',
                          style: TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.tint(AppTheme.errorColor, 0.12),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                        border: Border.all(
                          color: AppTheme.errorColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.errorTextColor,
                            size: 20,
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
                  ],

                  if (!_isDownloading) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TintedButton.neutral(
                          onPressed: () => Navigator.of(context).pop(),
                          label: 'Later',
                        ),
                        const SizedBox(width: 10),
                        TintedButton(
                          onPressed: _startUpdate,
                          label: 'Update Now',
                          color: AppTheme.brandPurple,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
