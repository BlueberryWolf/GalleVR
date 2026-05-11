import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class BlurrableQrCode extends StatefulWidget {
  final String revealedData;

  final String blurredData;

  final double size;

  final bool initiallyRevealed;

  final Function(bool isRevealed)? onVisibilityChanged;

  const BlurrableQrCode({
    super.key,
    required this.revealedData,
    required this.blurredData,
    this.size = 200,
    this.initiallyRevealed = false,
    this.onVisibilityChanged,
  });

  @override
  State<BlurrableQrCode> createState() => _BlurrableQrCodeState();
}

class _BlurrableQrCodeState extends State<BlurrableQrCode> {
  late bool _isRevealed;

  @override
  void initState() {
    super.initState();
    _isRevealed = widget.initiallyRevealed;
  }

  void _toggleVisibility() {
    setState(() {
      _isRevealed = !_isRevealed;
    });

    if (widget.onVisibilityChanged != null) {
      widget.onVisibilityChanged!(_isRevealed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              QrImageView(
                data: widget.revealedData,
                version: QrVersions.auto,
                size: widget.size,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
                backgroundColor: Colors.white,
              ),
              AnimatedOpacity(
                opacity: _isRevealed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: _isRevealed,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        color: Colors.white.withOpacity(0.1),
                        child: Center(
                          child: ElevatedButton.icon(
                            onPressed: _toggleVisibility,
                            icon: const Icon(Icons.visibility),
                            label: const Text('Reveal QR Code'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isRevealed ? 40 : 0,
            curve: Curves.easeInOut,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: AnimatedOpacity(
                opacity: _isRevealed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextButton.icon(
                    onPressed: _toggleVisibility,
                    icon: const Icon(Icons.visibility_off, size: 16),
                    label: const Text('Hide QR Code'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
