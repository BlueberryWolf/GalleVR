import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TintedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final Color color;
  final IconData? icon;
  final double? width;
  final bool dense;

  const TintedButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.color = AppTheme.primaryColor,
    this.icon,
    this.width,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? color : AppTheme.secondaryTextColor;

    return Material(
      color: enabled ? AppTheme.tint(color, 0.18) : AppTheme.buttonColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(
          color:
              enabled
                  ? color.withValues(alpha: 0.35)
                  : AppTheme.buttonBorderColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onPressed,
        child: Container(
          width: width,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 14 : 18,
            vertical: dense ? 8 : 12,
          ),
          child: Row(
            mainAxisSize: width != null ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 16 : 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: dense ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
