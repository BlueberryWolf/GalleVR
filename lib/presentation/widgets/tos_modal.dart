import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:ui';

import '../../data/services/tos_service.dart';
import '../theme/app_theme.dart';

class TOSModal extends StatefulWidget {
  final Function() onAccept;
  final Function() onDecline;
  final bool showDeclineButton;
  final String title;

  const TOSModal({
    super.key,
    required this.onAccept,
    required this.onDecline,
    this.showDeclineButton = true,
    this.title = 'Terms of Service',
  });

  @override
  State<TOSModal> createState() => _TOSModalState();
}

class _TOSModalState extends State<TOSModal> {
  final TOSService _tosService = TOSService();
  bool _isLoading = true;
  bool _isAccepting = false;
  bool _hasAccepted = false;
  Map<String, dynamic> _tosData = {};
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadTOSContent();
  }

  Future<void> _loadTOSContent() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final tosContent = await _tosService.getTOSContent();

      setState(() {
        _tosData = tosContent;
        _isLoading = false;
      });
    } catch (e) {
      developer.log('Error loading TOS content: $e', name: 'TOSModal');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load Terms of Service. Please try again.';
      });
    }
  }

  Future<void> _acceptTOS() async {
    if (_hasAccepted) return;

    setState(() {
      _isAccepting = true;
      _errorMessage = '';
    });

    try {
      final success = await _tosService.acceptTOS();

      if (success) {
        setState(() {
          _hasAccepted = true;
          _isAccepting = false;
        });

        widget.onAccept();
      } else {
        setState(() {
          _isAccepting = false;
          _errorMessage =
              'Failed to accept Terms of Service. Please try again.';
        });
      }
    } catch (e) {
      developer.log('Error accepting TOS: $e', name: 'TOSModal');
      setState(() {
        _isAccepting = false;
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
        ),

        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: isSmallScreen ? size.width * 0.9 : size.width * 0.7,
              height: size.height * 0.8,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  if (_tosData.containsKey('content') &&
                      _tosData['content'] is Map &&
                      (_tosData['content'] as Map).containsKey(
                        'effectiveDate',
                      )) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Effective Date: ${_formatDate((_tosData['content'] as Map)['effectiveDate'])}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ] else if (_tosData.containsKey('lastModified')) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last Updated: ${_formatDate(_tosData['lastModified'])}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),

                  Expanded(child: _buildContent()),

                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.showDeclineButton) ...[
                        TextButton(
                          onPressed: _isAccepting ? null : widget.onDecline,
                          child: const Text(
                            'Decline',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      ElevatedButton(
                        onPressed: _isAccepting ? null : _acceptTOS,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child:
                            _isAccepting
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text('Accept'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty && _tosData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadTOSContent,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_tosData.containsKey('content')) {
      final content = _tosData['content'];

      if (content is String) {
        return SingleChildScrollView(
          child: Text(content, style: const TextStyle(color: Colors.white)),
        );
      }

      if (content is Map && content.containsKey('message')) {
        return SingleChildScrollView(
          child: Text(
            content['message'],
            style: const TextStyle(color: Colors.white),
          ),
        );
      }

      if (content is Map &&
          content.containsKey('content') &&
          content['content'] is String) {
        return SingleChildScrollView(
          child: Text(
            content['content'],
            style: const TextStyle(color: Colors.white),
          ),
        );
      }
    }

    if (_tosData.containsKey('content') && _tosData['content'] is Map) {
      final contentMap = _tosData['content'] as Map;

      if (contentMap.containsKey('content') &&
          contentMap['content'] is String) {
        return SingleChildScrollView(
          child: Text(
            contentMap['content'],
            style: const TextStyle(color: Colors.white),
          ),
        );
      }
    }

    if (_tosData.containsKey('content') && _tosData['content'] is Map) {
      final contentMap = _tosData['content'] as Map;

      String mainContent = '';

      if (contentMap.containsKey('text') && contentMap['text'] is String) {
        mainContent = contentMap['text'];
      } else if (contentMap.containsKey('body') &&
          contentMap['body'] is String) {
        mainContent = contentMap['body'];
      } else if (contentMap.containsKey('message') &&
          contentMap['message'] is String) {
        mainContent = contentMap['message'];
      }

      if (mainContent.isNotEmpty) {
        return SingleChildScrollView(
          child: Text(mainContent, style: const TextStyle(color: Colors.white)),
        );
      }
    }

    if (_tosData.isEmpty || !_tosData.containsKey('content')) {
      return const Center(
        child: Text(
          'Terms of Service content not available.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    try {
      final contentObj = _tosData['content'];

      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      final String prettyJson = encoder.convert(contentObj);

      return SingleChildScrollView(
        child: Text(
          prettyJson,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      );
    } catch (e) {
      return SingleChildScrollView(
        child: Text(
          _tosData.toString(),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
  }

  String _formatDate(dynamic dateStr) {
    try {
      if (dateStr == null) return 'Unknown';

      final date = DateTime.parse(dateStr.toString());

      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];

      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr.toString();
    }
  }
}
