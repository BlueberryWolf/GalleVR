import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSwitch({super.key, required this.value, required this.onChanged});

  static const double _width = 44;
  static const double _height = 24;
  static const double _inset = 3.5;
  static const double _thumb = _height - _inset * 2;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
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
              curve: const Cubic(0.16, 1, 0.3, 1),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: _thumb,
                height: _thumb,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag - 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
