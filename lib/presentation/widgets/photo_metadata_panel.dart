import 'dart:ui';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:gallevr/data/models/log_metadata.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/photo_metadata.dart';
import '../theme/app_theme.dart';

// A widget that displays photo metadata in a panel
class PhotoMetadataPanel extends StatelessWidget {
  // The photo metadata to display
  final PhotoMetadata? metadata;

  // Whether the panel is open
  final bool isOpen;

  // Callback when the panel is closed
  final VoidCallback onClose;

  // Default constructor
  const PhotoMetadataPanel({
    super.key,
    required this.metadata,
    required this.isOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 300,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
            border: Border(
              left: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(-10, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with close button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Photo Info',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _HeaderCloseButton(onPressed: onClose),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: metadata == null
                    ? _buildNoMetadataMessage()
                    : _buildMetadataContent(context),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNoMetadataMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.white.withOpacity(0.15),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'No metadata available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.25),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      children: [
        // World info
        if (metadata?.world != null) ...[
          _buildSectionHeader('WORLD'),
          _InteractiveMetadataItem(
            onTap: () => _launchVRChatWorldUrl(metadata!.world!.id),
            child: _buildWorldContent(context, metadata!.world!),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 12),
        ],

        // Players list
        if (metadata?.players.isNotEmpty == true) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('PLAYERS'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${metadata!.players.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...metadata!.players.map((player) => _InteractiveMetadataItem(
            onTap: () => _launchVRChatUserUrl(player.id),
            child: _buildPlayerContent(player),
            margin: const EdgeInsets.only(bottom: 4),
          )),
        ],

        // No metadata message
        if (metadata?.world == null && metadata?.players.isEmpty == true)
          _buildNoMetadataMessage(),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildWorldContent(BuildContext context, WorldInfo world) {
    return Row(
      children: [
        Icon(
          Icons.public_rounded,
          color: Colors.white.withOpacity(0.7),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                world.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_forward_ios_rounded,
          color: Colors.white.withOpacity(0.4),
          size: 12,
        ),
      ],
    );
  }

  Widget _buildPlayerContent(Player player) {
    return Row(
      children: [
        Icon(
          Icons.person_outline_rounded,
          color: Colors.white.withOpacity(0.7),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            player.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          Icons.arrow_forward_ios_rounded,
          color: Colors.white.withOpacity(0.4),
          size: 12,
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
      developer.log('Error launching world url: $e', name: 'PhotoMetadataPanel', error: e);
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
      developer.log('Error launching user url: $e', name: 'PhotoMetadataPanel', error: e);
    }
  }
}

class _InteractiveMetadataItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets? margin;

  const _InteractiveMetadataItem({
    required this.child,
    required this.onTap,
    this.margin,
  });

  @override
  State<_InteractiveMetadataItem> createState() => _InteractiveMetadataItemState();
}

class _InteractiveMetadataItemState extends State<_InteractiveMetadataItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: widget.margin,
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white.withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: widget.child,
          ),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: IconButton(
        icon: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withOpacity(0.1) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),
        onPressed: widget.onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
