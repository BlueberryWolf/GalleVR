import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  static const double _width = 40;
  static const double _height = 22;
  static const double _inset = 3;
  static const double _dot = _height - _inset * 2;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(_inset),
            decoration: BoxDecoration(
              color: value ? AppTheme.brandPurpleDeep : AppTheme.switchOffColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusTag),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: _dot,
                height: _dot,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag - 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
