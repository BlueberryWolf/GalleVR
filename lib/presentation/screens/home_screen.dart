import 'dart:io';
import 'package:flutter/material.dart';

import 'monitor_screen.dart';
import 'photos_screen.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/refresh_button.dart';
import '../widgets/tinted_button.dart';
import '../widgets/walkthrough_dialog.dart';
import '../controllers/photos_controller.dart';
import '../../data/services/photo_upload_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  bool _isSidebarCollapsed = false;
  final GlobalKey _stackKey = GlobalKey();
  final Set<int> _builtTabs = {};

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final PhotosController _photosController = PhotosController();
  bool _showCurlWarning = false;

  late final List<_NavItem> _navItems;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialTabIndex;
    _builtTabs.add(_currentIndex);
    _checkCurl();

    _navItems = [
      _NavItem(
        icon: Icons.photo_library_rounded,
        label: 'Photos',
        screen: PhotosScreen(controller: _photosController),
        iconColor: AppTheme.iconPhotos,
        headerAccent: AppTheme.iconPhotos,
      ),
      _NavItem(
        icon: Icons.monitor_rounded,
        label: 'Monitor',
        screen: const MonitorScreen(),
        iconColor: AppTheme.iconFeed,
        headerAccent: AppTheme.iconFeed,
      ),
      _NavItem(
        icon: Icons.account_circle_rounded,
        label: 'Account',
        screen: const AccountScreen(),
        iconColor: AppTheme.iconPlayers,
        headerAccent: AppTheme.iconPlayers,
      ),
      _NavItem(
        icon: Icons.settings_rounded,
        label: 'Settings',
        screen: const SettingsScreen(),
        iconColor: AppTheme.iconSettings,
        headerAccent: AppTheme.brandPurple,
      ),
    ];

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.value = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WalkthroughDialog.showIfRequired(context);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _photosController.dispose();
    super.dispose();
  }

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = _isSmallScreen(context);
    final contentStack = Expanded(
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: IndexedStack(
            key: _stackKey,
            index: _currentIndex,
            children: [
              for (var i = 0; i < _navItems.length; i++)
                _builtTabs.contains(i) || i == _currentIndex
                    ? _navItems[i].screen
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      bottomNavigationBar: isSmallScreen ? _buildBottomNavBar(context) : null,
      body: Row(
        children: [
          if (!isSmallScreen) _buildDesktopSidebar(),
          Expanded(
            child: RepaintBoundary(
              child: Column(
                children: [
                  _buildHeader(isSmallScreen),
                  if (_showCurlWarning) _buildCurlWarningBanner(),
                  contentStack,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _checkCurl() async {
    if (Platform.isWindows || Platform.isLinux) {
      final hasCurl = await PhotoUploadService.checkCurlInstalled();
      if (!hasCurl && mounted) {
        setState(() {
          _showCurlWarning = true;
        });
      }
    }
  }

  Widget _buildCurlWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.tint(AppTheme.warningColor, 0.10),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.warningColor.withValues(alpha: 0.30),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.warningColor,
            size: 18,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'curl is not installed on your system. GalleVR will use a slower fallback uploader.',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _GhostIconButton(
            icon: Icons.close_rounded,
            iconSize: 18,
            size: 32,
            color: AppTheme.secondaryTextColor,
            tooltip: 'Dismiss',
            onTap: () {
              setState(() {
                _showCurlWarning = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    final current = _navItems[_currentIndex];

    return Container(
      height: isSmallScreen ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 28),
      decoration: const BoxDecoration(
        color: AppTheme.chromeColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.headerBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (isSmallScreen)
            Container(
              height: 32,
              width: 32,
              margin: const EdgeInsets.only(right: 12),
              child: Image.asset(
                'assets/images/square.png',
                fit: BoxFit.contain,
              ),
            ),
          Expanded(child: _buildHeaderTitle(current, isSmallScreen)),
          if (current.label == 'Photos')
            ValueListenableBuilder<PhotosState>(
              valueListenable: _photosController,
              builder: (context, state, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSelectButton(state, isSmallScreen),
                    const SizedBox(width: 8),
                    RefreshButton(
                      isLoading: state.isLoading,
                      onTap: () => _photosController.refresh(forceSync: true),
                      tooltip: 'Refresh Photos',
                    ),
                    if (!isSmallScreen) ...[
                      const SizedBox(width: 4),
                      _GhostIconButton(
                        icon: Icons.help_outline_rounded,
                        tooltip: 'Show Walkthrough',
                        onTap:
                            () => WalkthroughDialog.showIfRequired(
                              context,
                              force: true,
                            ),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderTitle(_NavItem item, bool isSmallScreen) {
    final fontSize = isSmallScreen ? 20.0 : 26.0;
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: fontSize * -0.025,
      height: 1.15,
      color: AppTheme.textColor,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'Your '),
          TextSpan(
            text: item.label,
            style: TextStyle(color: item.headerAccent),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSelectButton(PhotosState state, bool isSmallScreen) {
    final isSelectionMode = state.isSelectionMode;
    final color = isSelectionMode ? AppTheme.errorColor : AppTheme.brandPurple;

    if (isSmallScreen) {
      return TintedButton(
        onPressed: _photosController.toggleSelectionMode,
        label: isSelectionMode ? 'Cancel' : 'Select',
        color: color,
        icon:
            isSelectionMode
                ? Icons.close_rounded
                : Icons.library_add_check_outlined,
        height: 40,
        dense: true,
      );
    }

    return TintedButton(
      onPressed: _photosController.toggleSelectionMode,
      label: isSelectionMode ? 'Cancel' : 'Select',
      color: color,
      icon:
          isSelectionMode
              ? Icons.close_rounded
              : Icons.library_add_check_outlined,
      height: 44,
    );
  }

  Widget _buildDesktopSidebar() {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: const Cubic(0.25, 0.1, 0.25, 1.0),
        width: _isSidebarCollapsed ? 70 : 250,
        decoration: const BoxDecoration(
          color: AppTheme.chromeColor,
          border: Border(
            right: BorderSide(color: AppTheme.sidebarBorderColor, width: 1),
          ),
        ),
        child: Column(
          children: [
            _buildSidebarHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                children: _buildNavItems(),
              ),
            ),
            _buildSidebarToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.chromeColor,
          border: Border(
            top: BorderSide(color: AppTheme.headerBorderColor, width: 1),
          ),
        ),
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children:
              _navItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = index == _currentIndex;

                return Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () => _selectNavItem(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: isSelected ? 1.1 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              item.icon,
                              color: item.iconColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                              color:
                                  isSelected
                                      ? AppTheme.textColor
                                      : AppTheme.secondaryTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return SizedBox(
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: _isSidebarCollapsed ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Image.asset(
                'assets/images/logo.png',
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _isSidebarCollapsed ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Image.asset(
              'assets/images/square.png',
              height: 48,
              width: 48,
              fit: BoxFit.contain,
            ),
          ),
          const Positioned(
            bottom: 0,
            left: 16,
            right: 16,
            child: Divider(height: 1, color: Color(0x1AFFFFFF)),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle() {
    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 16,
          right: 16,
          child: Divider(height: 1, color: Color(0x1AFFFFFF)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: _SidebarNavTile(
            icon:
                _isSidebarCollapsed
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
            iconColor: AppTheme.secondaryTextColor,
            label: _isSidebarCollapsed ? 'Expand' : 'Collapse',
            isSelected: false,
            isCollapsed: _isSidebarCollapsed,
            height: 44,
            tooltip: _isSidebarCollapsed ? 'Expand sidebar' : null,
            onTap: _toggleSidebar,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildNavItems() {
    return _navItems.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isSelected = index == _currentIndex;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _SidebarNavTile(
          icon: item.icon,
          iconColor: item.iconColor,
          label: item.label,
          isSelected: isSelected,
          isCollapsed: _isSidebarCollapsed,
          tooltip: _isSidebarCollapsed ? item.label : null,
          onTap: () => _selectNavItem(index),
        ),
      );
    }).toList();
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarCollapsed = !_isSidebarCollapsed;
    });
  }

  void _selectNavItem(int index) {
    if (index == _currentIndex) return;

    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = index;
        _builtTabs.add(index);
      });
      _fadeController.forward();
    });
  }
}

class _SidebarNavTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final double height;
  final String? tooltip;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.height = 48,
    this.tooltip,
  });

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isSelected
            ? AppTheme.buttonColor
            : _isHovered
            ? AppTheme.buttonHoverColor
            : Colors.transparent;

    final textColor =
        widget.isSelected
            ? AppTheme.textColor
            : _isHovered
            ? AppTheme.bodyTextColor
            : AppTheme.secondaryTextColor;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: AnimatedScale(
                    scale: (widget.isSelected || _isHovered) ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Icon(widget.icon, color: widget.iconColor, size: 22),
                  ),
                ),
              ),
              if (!widget.isCollapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          widget.isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: tile);
    }
    return tile;
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;
  final Color iconColor;
  final Color headerAccent;

  _NavItem({
    required this.icon,
    required this.label,
    required this.screen,
    required this.iconColor,
    required this.headerAccent,
  });
}

class _GhostIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final double iconSize;
  final Color color;

  const _GhostIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 44,
    this.iconSize = 20,
    this.color = AppTheme.textColor,
  });

  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _isHovered ? AppTheme.buttonHoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _isHovered ? AppTheme.textColor : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
