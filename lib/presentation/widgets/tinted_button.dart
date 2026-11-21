import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TintedButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final Color? color;
  final IconData? icon;
  final IconData? appendIcon;
  final double? width;
  final double? height;
  final bool dense;
  final bool loading;

  const TintedButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.color = AppTheme.brandPurple,
    this.icon,
    this.appendIcon,
    this.width,
    this.height,
    this.dense = false,
    this.loading = false,
  });

  const TintedButton.neutral({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.appendIcon,
    this.width,
    this.height,
    this.dense = false,
    this.loading = false,
  }) : color = null;

  @override
  State<TintedButton> createState() => _TintedButtonState();
}

class _TintedButtonState extends State<TintedButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final tint = widget.color;
    final isNeutral = tint == null;

    final Color bgColor;
    final Color borderColor;
    final Color foregroundColor;

    if (isNeutral) {
      bgColor =
          _isHovered && enabled
              ? AppTheme.buttonHoverColor
              : AppTheme.buttonColor;
      borderColor =
          _isHovered && enabled
              ? AppTheme.cardHoverBorderColor
              : AppTheme.buttonBorderColor;
      foregroundColor = const Color(0xFFE0E0E0);
    } else {
      bgColor = AppTheme.tint(tint, _isHovered && enabled ? 0.30 : 0.22);
      borderColor = AppTheme.tintBorder(
        tint,
        _isHovered && enabled ? 0.50 : 0.35,
      );
      foregroundColor = Colors.white;
    }

    return Opacity(
      opacity: (widget.onPressed == null && !widget.loading) ? 0.5 : 1.0,
      child: MouseRegion(
        cursor:
            widget.loading
                ? SystemMouseCursors.progress
                : enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.ease,
            width: widget.width,
            height: widget.height,
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 14 : 16,
              vertical: widget.height != null ? 0 : (widget.dense ? 8 : 11),
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: borderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: widget.loading ? 0.0 : 1.0,
                  child: Row(
                    mainAxisSize:
                        widget.width != null
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: widget.dense ? 16 : 18,
                          color: foregroundColor,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: widget.dense ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.appendIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          widget.appendIcon,
                          size: widget.dense ? 16 : 18,
                          color: foregroundColor,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foregroundColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
