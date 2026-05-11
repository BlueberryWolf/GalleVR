import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../../../../data/models/photo_metadata.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/cached_image.dart';

class PhotoGridItem extends StatefulWidget {
  final FileSystemEntity entity;
  final PhotoMetadata? metadata;
  final VoidCallback onTap;
  final VoidCallback onOptionsPressed;

  const PhotoGridItem({
    super.key,
    required this.entity,
    required this.metadata,
    required this.onTap,
    required this.onOptionsPressed,
  });

  @override
  State<PhotoGridItem> createState() => _PhotoGridItemState();

  static Widget skeleton() {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorderColor, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.white.withOpacity(0.05)),
              const Center(
                child: Icon(
                  Icons.photo_outlined,
                  color: Colors.white10,
                  size: 48,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(height: 32, color: Colors.black26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoGridItemState extends State<PhotoGridItem> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUploaded = widget.metadata?.galleryUrl != null;
    final filename =
        widget.metadata?.filename ?? path.basename(widget.entity.path);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, child) {
                  final bool isGreyedOut = !isUploaded && !hovered;
                  return AnimatedScale(
                    scale: hovered ? 1.04 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      foregroundDecoration: BoxDecoration(
                        color:
                            hovered
                                ? Colors.white.withOpacity(0.05)
                                : Colors.transparent,
                      ),
                      child: ColorFiltered(
                        colorFilter:
                            isGreyedOut
                                ? const ColorFilter.matrix(<double>[
                                  0.2126,
                                  0.7152,
                                  0.0722,
                                  0,
                                  0,
                                  0.2126,
                                  0.7152,
                                  0.0722,
                                  0,
                                  0,
                                  0.2126,
                                  0.7152,
                                  0.0722,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ])
                                : const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.saturation,
                                ),
                        child: CachedImage(
                          filePath: widget.entity.path,
                          fit: BoxFit.cover,
                          thumbnailSize: 400,
                          highQuality: false,
                          opacity: isGreyedOut ? 0.6 : 1.0,
                        ),
                      ),
                    ),
                  );
                },
              ),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  onHover: (value) => _isHovered.value = value,
                  borderRadius: BorderRadius.circular(16),
                  mouseCursor: SystemMouseCursors.click,
                ),
              ),

              _buildTopGradient(),
              _buildTopMetadata(),
              _buildTopRightActions(),

              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, child) {
                  return IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              hovered
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dt.month - 1];

    String daySuffix = 'th';
    if (dt.day == 1 || dt.day == 21 || dt.day == 31)
      daySuffix = 'st';
    else if (dt.day == 2 || dt.day == 22)
      daySuffix = 'nd';
    else if (dt.day == 3 || dt.day == 23)
      daySuffix = 'rd';

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    final minute = dt.minute.toString().padLeft(2, '0');

    return '$month ${dt.day}$daySuffix ${dt.year}, $hour:$minute $ampm';
  }

  Widget _buildTopGradient() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 100,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.black.withOpacity(0.2),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopMetadata() {
    String dateStr = '';
    if (widget.metadata != null) {
      dateStr = _formatDate(widget.metadata!.takenDate);
    }

    final worldName = widget.metadata?.world?.name;
    final playerCount = widget.metadata?.players.length ?? 0;

    return Positioned(
      top: 12,
      left: 12,
      right: 80,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (worldName != null) ...[
                  const Icon(
                    Icons.public_rounded,
                    size: 13,
                    color: Color(0xFF3b82f6),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      worldName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 2),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (playerCount > 0) ...[
                  if (worldName != null) const SizedBox(width: 8),
                  const Icon(
                    Icons.people_alt_rounded,
                    size: 13,
                    color: Color(0xFF4ade80),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$playerCount',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 2),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRightActions() {
    return Positioned(
      top: 12,
      right: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.metadata?.galleryUrl != null)
            _buildIndicatorButton(
              icon: Icons.cloud_done_rounded,
              color: const Color(0xFF4ade80),
              tooltip: 'Uploaded to Gallery',
              onPressed: widget.onTap,
            ),
        ],
      ),
    );
  }

  Widget _buildIndicatorButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color color = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, size: 16, color: color.withOpacity(0.9)),
        ),
      ),
    );
  }
}
