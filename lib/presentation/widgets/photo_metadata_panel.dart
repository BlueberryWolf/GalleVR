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
    if (!isOpen) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: MediaQuery.of(context).size.width * 0.8,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(179),
        border: Border(
          left: BorderSide(
            color: Colors.white.withAlpha(26),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(128),
            blurRadius: 10,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Photo Info',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Divider
          Divider(color: Colors.white.withAlpha(26)),

          // Content
          Expanded(
            child: metadata == null
                ? _buildNoMetadataMessage()
                : _buildMetadataContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMetadataMessage() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.white54,
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            'No metadata available',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // World info
          if (metadata?.world != null) ...[
            _buildSectionHeader('World'),
            _buildWorldInfo(context, metadata!.world!),
            const SizedBox(height: 24),
          ],

          // Players list
          if (metadata?.players.isNotEmpty == true) ...[
            _buildSectionHeader('Players (${metadata!.players.length})'),
            ...metadata!.players.map((player) => _buildPlayerItem(player)),
          ],

          // No metadata message
          if (metadata?.world == null && metadata?.players.isEmpty == true)
            _buildNoMetadataMessage(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withAlpha(179),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildWorldInfo(BuildContext context, WorldInfo world) {
    return Card(
      color: AppTheme.surfaceColor.withAlpha(77),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.white.withAlpha(26),
        ),
      ),
      child: InkWell(
        onTap: () => _launchVRChatWorldUrl(world.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(
                Icons.public,
                color: Colors.blue.shade300,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      world.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (world.instanceId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Instance: ${world.instanceId}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(179),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                color: Colors.white.withAlpha(128),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerItem(Player player) {
    return Card(
      color: AppTheme.surfaceColor.withAlpha(51),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.white.withAlpha(13),
        ),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _launchVRChatUserUrl(player.id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.person,
                color: Colors.green.shade300,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  player.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withAlpha(77),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _launchVRChatWorldUrl(String worldId) async {
    final url = Uri.parse('https://vr.blueberry.coffee/world/$worldId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _launchVRChatUserUrl(String userId) async {
    final url = Uri.parse('https://vr.blueberry.coffee/user/$userId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
