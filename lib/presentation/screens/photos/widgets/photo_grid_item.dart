import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/models/photo_metadata.dart';
import '../../../../core/utils/tag_parser.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/cached_image.dart';

class PhotoGridItem extends StatefulWidget {
  final FileSystemEntity entity;
  final PhotoMetadata? metadata;
  final VoidCallback onTap;
  final VoidCallback onOptionsPressed;
  final bool isSelected;
  final bool isSelectionMode;
  final int decodeWidth;

  const PhotoGridItem({
    super.key,
    required this.entity,
    required this.metadata,
    required this.onTap,
    required this.onOptionsPressed,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.decodeWidth = 400,
  });

  @override
  State<PhotoGridItem> createState() => _PhotoGridItemState();

  static Widget skeleton() {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBackgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.cardBorderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.white.withValues(alpha: 0.03)),
              const Center(
                child: Icon(
                  Icons.photo_outlined,
                  color: Colors.white10,
                  size: 40,
                ),
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

  static final Color _hoverBorderColor = Color.lerp(
    AppTheme.cardBorderColor,
    AppTheme.brandPurple,
    0.35,
  )!;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUploaded = widget.metadata?.galleryUrl != null;

    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        builder: (context, hovered, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: const Cubic(0.16, 1, 0.3, 1),
            transform: Matrix4.translationValues(0, hovered ? -3.0 : 0.0, 0),
            decoration: BoxDecoration(
              color: AppTheme.cardBackgroundColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              boxShadow: [
                BoxShadow(
                  color:
                      hovered
                          ? const Color(0x80000000)
                          : const Color(0x66000000),
                  blurRadius: hovered ? 32 : 24,
                  offset: Offset(0, hovered ? 12 : 8),
                ),
              ],
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, child) {
                  final bool isGreyedOut =
                      !isUploaded && !hovered && !widget.isSelected;
                  return AnimatedScale(
                    scale: hovered && !widget.isSelected ? 1.04 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    curve: const Cubic(0.16, 1, 0.3, 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      foregroundDecoration: BoxDecoration(
                        color:
                            widget.isSelected
                                ? AppTheme.brandPurple.withValues(alpha: 0.14)
                                : hovered
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.transparent,
                      ),
                      child: CachedImage(
                        filePath: widget.entity.path,
                        fit: BoxFit.cover,
                        thumbnailSize: widget.decodeWidth,
                        highQuality: false,
                        greyscale: isGreyedOut,
                        opacity: isGreyedOut ? 0.6 : 1.0,
                      ),
                    ),
                  );
                },
              ),

              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, _) {
                  return IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: hovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xB3000000), Color(0x00000000)],
                            stops: [0.0, 0.45],
                          ),
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
                  hoverColor: Colors.transparent,
                  splashColor: Colors.white.withValues(alpha: 0.08),
                  highlightColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  mouseCursor: SystemMouseCursors.click,
                ),
              ),

              _buildTopGradient(),
              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, child) {
                  return _buildSelectionIndicator(hovered);
                },
              ),
              _buildTopMetadata(),
              _buildTopRightActions(),

              ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, child) {
                  return IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusCard,
                        ),
                        border: Border.all(
                          color:
                              widget.isSelected
                                  ? AppTheme.brandPurple
                                  : hovered
                                  ? _hoverBorderColor
                                  : AppTheme.cardBorderColor,
                          width: widget.isSelected ? 2 : 1,
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
    if (dt.day == 1 || dt.day == 21 || dt.day == 31) {
      daySuffix = 'st';
    } else if (dt.day == 2 || dt.day == 22) {
      daySuffix = 'nd';
    } else if (dt.day == 3 || dt.day == 23) {
      daySuffix = 'rd';
    }

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    final minute = dt.minute.toString().padLeft(2, '0');

    return '$month ${dt.day}$daySuffix ${dt.year}, $hour:$minute $ampm';
  }

  Widget _buildTopGradient() {
    return const Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 96,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xD9000000), Color(0xA6000000), Color(0x00000000)],
              stops: [0.0, 0.55, 1.0],
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
    const textShadow = [
      Shadow(color: Color(0xE6000000), blurRadius: 3, offset: Offset(0, 1)),
    ];

    return Positioned(
      top: 12,
      left: 12,
      right: 52,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  shadows: textShadow,
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
                      color: AppTheme.iconWorld,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        stripResoniteTags(worldName),
                        style: const TextStyle(
                          color: AppTheme.bodyTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          shadows: textShadow,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (playerCount > 0) ...[
                    if (worldName != null) const SizedBox(width: 10),
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 13,
                      color: AppTheme.iconPlayers,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$playerCount',
                      style: const TextStyle(
                        color: AppTheme.bodyTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                        shadows: textShadow,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopRightActions() {
    if (widget.metadata?.galleryUrl == null) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      right: 10,
      child: Tooltip(
        message: 'Uploaded to Gallery',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: const Icon(
                Icons.cloud_done_rounded,
                size: 16,
                color: AppTheme.successColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionIndicator(bool hovered) {
    final isUploaded = widget.metadata?.galleryUrl != null;
    if (!widget.isSelectionMode || isUploaded) return const SizedBox.shrink();

    return Positioned(
      left: 10,
      bottom: 10,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color:
                widget.isSelected
                    ? AppTheme.brandPurple
                    : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppTheme.radiusTag),
            border: Border.all(
              color:
                  widget.isSelected
                      ? AppTheme.brandPurple
                      : Colors.white.withValues(alpha: 0.85),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child:
              widget.isSelected
                  ? const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  )
                  : null,
        ),
      ),
    );
  }
}
