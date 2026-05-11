import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

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
  late AnimationController _controller;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didUpdateWidget(RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading != oldWidget.isLoading) {
      if (widget.isLoading) {
        _controller.repeat();
      } else {
        _controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.elasticOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleHoverChange(bool hovered) {
    setState(() => _isHovered = hovered);
    if (!widget.isLoading) {
      if (hovered) {
        _controller.animateTo(
          0.25,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else {
        _controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double scale = 1.0;
    if (_isPressed) {
      scale = 0.92;
    } else if (_isHovered && !widget.isLoading) {
      scale = 1.05;
    }

    return MouseRegion(
      onEnter: (_) => _handleHoverChange(true),
      onExit: (_) => _handleHoverChange(false),
      child: Tooltip(
        message: widget.tooltip ?? 'Refresh',
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.isLoading ? null : widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                  _isPressed ? 0.15 : (_isHovered ? 0.1 : 0.05),
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(_isHovered ? 0.2 : 0.1),
                  width: 1,
                ),
                boxShadow: [
                  if (_isHovered && !widget.isLoading)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Center(
                child: RotationTransition(
                  turns: _controller,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color:
                        _isHovered || widget.isLoading
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
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
