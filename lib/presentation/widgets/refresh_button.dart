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
    duration: const Duration(milliseconds: 1000),
  );

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
    return IconButton(
      onPressed: widget.isLoading ? null : widget.onTap,
      tooltip: widget.tooltip ?? 'Refresh',
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(Icons.refresh_rounded, size: 20),
      ),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        backgroundColor: AppTheme.buttonColor,
        disabledBackgroundColor: AppTheme.buttonColor,
        hoverColor: AppTheme.buttonHoverColor,
        foregroundColor: AppTheme.textColor,
        disabledForegroundColor: AppTheme.textColor,
        side: const BorderSide(color: AppTheme.buttonBorderColor),
      ),
    );
  }
}
