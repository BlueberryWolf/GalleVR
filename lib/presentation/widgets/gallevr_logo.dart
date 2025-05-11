import 'package:flutter/material.dart';

class GalleVRLogo extends StatelessWidget {
  final double height;

  final bool showText;

  const GalleVRLogo({super.key, this.height = 32, this.showText = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          AnimatedOpacity(
            opacity: showText ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, showText ? 0 : -4, 0),

              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: height,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          AnimatedOpacity(
            opacity: showText ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, showText ? 4 : 0, 0),

              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/square.png',
                  height: height,
                  width: height,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
