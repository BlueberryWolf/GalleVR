import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AvatarCircle extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final Color color;
  final IconData fallbackIcon;

  const AvatarCircle({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.color,
    this.fallbackIcon = Icons.person_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Icon(fallbackIcon, size: size / 2, color: color),
    );

    return Container(
      width: size,
      height: size,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppTheme.tint(color, 0.15),
          child:
              imageUrl != null
                  ? Image.network(
                    imageUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  )
                  : fallback,
        ),
      ),
    );
  }
}
