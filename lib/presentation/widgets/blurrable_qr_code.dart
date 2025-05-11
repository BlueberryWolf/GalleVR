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
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
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
              QrImageView(
                data: _isRevealed ? widget.revealedData : widget.blurredData,
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
              if (_isRevealed) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _toggleVisibility,
                  icon: const Icon(Icons.visibility_off, size: 16),
                  label: const Text('Hide QR Code'),
                ),
              ],
            ],
          ),
        ),

        if (!_isRevealed)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: widget.size + 16,
                height: widget.size + 16,
                color: Colors.black.withAlpha(51),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _toggleVisibility,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Reveal QR Code'),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
