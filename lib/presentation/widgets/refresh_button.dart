import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RefreshButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final String? tooltip;

  const RefreshButton({
    super.key,
    required this.isLoading,
    required this.onTap,
    this.tooltip,
  });

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) _controller.repeat();
  }

  @override
  void didUpdateWidget(RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading == oldWidget.isLoading) return;
    if (widget.isLoading) {
      _controller.repeat();
    } else {
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? 'Refresh',
      child: MouseRegion(
        cursor:
            widget.isLoading
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.isLoading ? null : widget.onTap,
          child: Opacity(
            opacity: widget.isLoading ? 0.5 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: const Cubic(0.16, 1, 0.3, 1),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    _isHovered && !widget.isLoading
                        ? AppTheme.buttonHoverColor
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              alignment: Alignment.center,
              child: AnimatedRotation(
                turns: !widget.isLoading && _isHovered ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: const Cubic(0.16, 1, 0.3, 1),
                child: RotationTransition(
                  turns: _controller,
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
