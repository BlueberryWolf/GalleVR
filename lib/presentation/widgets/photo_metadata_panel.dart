import 'dart:async';
import 'dart:ui';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gallevr/data/models/log_metadata.dart';
import 'package:gallevr/core/utils/tag_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/photo_metadata.dart';
import '../theme/app_theme.dart';

class PhotoMetadataPanel extends StatelessWidget {
  final PhotoMetadata? metadata;
  final String? filename;
  final bool isOpen;
  final VoidCallback onClose;

  const PhotoMetadataPanel({
    super.key,
    required this.metadata,
    this.filename,
    required this.isOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFilename = filename ?? metadata?.filename;

    return Material(
      color: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 360,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xCC08080C),
              border: Border(
                left: BorderSide(color: Color(0x1AFFFFFF), width: 1),
              ),
            ),
            child: SafeArea(
              left: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Photo Info',
                          style: TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _HeaderCloseButton(onPressed: onClose),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        metadata == null && resolvedFilename == null
                            ? _buildNoMetadataMessage()
                            : _buildMetadataContent(context, resolvedFilename),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoMetadataMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.info_outline_rounded,
              color: AppTheme.secondaryTextColor,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'No additional information',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataContent(BuildContext context, String? resolvedFilename) {
    final hasWorld = metadata?.world != null;
    final hasPlayers = metadata?.players.isNotEmpty == true;
    final hasFile = resolvedFilename != null && resolvedFilename.isNotEmpty;

    if (!hasWorld && !hasPlayers && !hasFile) {
      return _buildNoMetadataMessage();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        if (hasWorld) ...[
          _buildSectionHeader('World'),
          _InteractiveMetadataItem(
            onTap: () => _launchVRChatWorldUrl(metadata!.world!.id),
            builder: (hovered) => _buildWorldContent(metadata!.world!, hovered),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          const SizedBox(height: 12),
        ],

        if (hasPlayers) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('Players'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusTag),
                ),
                child: Text(
                  '${metadata!.players.length}',
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...metadata!.players.map(
            (player) => _InteractiveMetadataItem(
              onTap: () => _launchVRChatUserUrl(player.id),
              margin: const EdgeInsets.only(bottom: 2),
              builder: (hovered) => _buildPlayerContent(player, hovered),
            ),
          ),
        ],

        if (hasFile) ...[
          if (hasWorld || hasPlayers) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            const SizedBox(height: 12),
          ],
          _buildSectionHeader('File'),
          _CopyableFilenameField(value: resolvedFilename),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildWorldContent(WorldInfo world, bool hovered) {
    return Row(
      children: [
        Icon(
          Icons.public_rounded,
          color: hovered ? AppTheme.primaryLightColor : AppTheme.iconWorld,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            parseResoniteTags(
              world.name,
              TextStyle(
                color: hovered ? AppTheme.primaryLightColor : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.arrow_forward_rounded,
          color:
              hovered
                  ? AppTheme.primaryLightColor
                  : Colors.white.withValues(alpha: 0.4),
          size: 15,
        ),
      ],
    );
  }

  Widget _buildPlayerContent(Player player, bool hovered) {
    return Row(
      children: [
        Icon(
          Icons.person_rounded,
          color:
              hovered
                  ? AppTheme.primaryLightColor
                  : Colors.white.withValues(alpha: 0.7),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            player.name,
            style: TextStyle(
              color: hovered ? AppTheme.primaryLightColor : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.arrow_forward_rounded,
          color:
              hovered
                  ? AppTheme.primaryLightColor
                  : Colors.white.withValues(alpha: 0.4),
          size: 15,
        ),
      ],
    );
  }

  void _launchVRChatWorldUrl(String worldId) async {
    final url = Uri.parse('https://gallevr.app/world/$worldId');
    try {
      bool launched = false;
      if (await canLaunchUrl(url)) {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!launched) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log(
        'Error launching world url: $e',
        name: 'PhotoMetadataPanel',
        error: e,
      );
    }
  }

  void _launchVRChatUserUrl(String userId) async {
    final url = Uri.parse('https://gallevr.app/user/$userId');
    try {
      bool launched = false;
      if (await canLaunchUrl(url)) {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (!launched) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log(
        'Error launching user url: $e',
        name: 'PhotoMetadataPanel',
        error: e,
      );
    }
  }
}

class _CopyableFilenameField extends StatefulWidget {
  final String value;

  const _CopyableFilenameField({required this.value});

  @override
  State<_CopyableFilenameField> createState() => _CopyableFilenameFieldState();
}

class _CopyableFilenameFieldState extends State<_CopyableFilenameField> {
  bool _copied = false;
  bool _isHovered = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.value,
              style: const TextStyle(
                color: AppTheme.bodyTextColor,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _copied ? 'Copied' : 'Copy',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onTap: _copy,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        _isHovered
                            ? AppTheme.buttonHoverColor
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: 16,
                    color:
                        _copied
                            ? AppTheme.successColor
                            : _isHovered
                            ? Colors.white
                            : AppTheme.secondaryTextColor,
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

class _InteractiveMetadataItem extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  final VoidCallback onTap;
  final EdgeInsets? margin;

  const _InteractiveMetadataItem({
    required this.builder,
    required this.onTap,
    this.margin,
  });

  @override
  State<_InteractiveMetadataItem> createState() =>
      _InteractiveMetadataItemState();
}

class _InteractiveMetadataItemState extends State<_InteractiveMetadataItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: widget.margin,
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: widget.builder(_isHovered),
        ),
      ),
    );
  }
}

class _HeaderCloseButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _HeaderCloseButton({required this.onPressed});

  @override
  State<_HeaderCloseButton> createState() => _HeaderCloseButtonState();
}

class _HeaderCloseButtonState extends State<_HeaderCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _isHovered ? AppTheme.buttonHoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.close_rounded,
              color:
                  _isHovered
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
