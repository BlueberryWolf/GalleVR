import 'package:flutter/material.dart';

import 'monitor_screen.dart';
import 'photos_screen.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/refresh_button.dart';
import '../widgets/walkthrough_dialog.dart';
import '../controllers/photos_controller.dart';
import '../../data/services/photo_upload_service.dart';
import 'dart:io';

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
        iconColor: AppTheme.accentPink,
      ),
      _NavItem(
        icon: Icons.monitor_rounded,
        label: 'Monitor',
        screen: const MonitorScreen(),
        iconColor: AppTheme.accentCyan,
      ),
      _NavItem(
        icon: Icons.account_circle_rounded,
        label: 'Account',
        screen: const AccountScreen(),
        iconColor: AppTheme.successColor,
      ),
      _NavItem(
        icon: Icons.settings_rounded,
        label: 'Settings',
        screen: const SettingsScreen(),
        iconColor: AppTheme.secondaryTextColor,
      ),
    ];

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
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
        color: AppTheme.tint(AppTheme.warningColor, 0.12),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.warningColor.withValues(alpha: 0.3),
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
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppTheme.secondaryTextColor,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
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
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBase,
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (isSmallScreen)
            Container(
              height: 40,
              width: 40,
              margin: const EdgeInsets.only(right: 12),
              child: Image.asset(
                'assets/images/square.png',
                fit: BoxFit.contain,
              ),
            ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHeaderTitle(isSmallScreen),
              if (!isSmallScreen) _buildHeaderSubtext(),
            ],
          ),

          const Spacer(),

          if (!isSmallScreen) ...[
            if (_navItems[_currentIndex].label == 'Photos')
              ValueListenableBuilder<PhotosState>(
                valueListenable: _photosController,
                builder: (context, state, child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSelectButton(state),
                      const SizedBox(width: 12),
                      RefreshButton(
                        isLoading: state.isLoading,
                        onTap: () => _photosController.refresh(forceSync: true),
                        tooltip: 'Refresh Photos',
                      ),
                      const SizedBox(width: 12),
                      _HelpButton(
                        onTap:
                            () => WalkthroughDialog.showIfRequired(
                              context,
                              force: true,
                            ),
                        tooltip: 'Show Walkthrough',
                      ),
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  static const Map<String, (List<Color>, IconData, String)> _sectionHeaders = {
    'Photos': (
      [AppTheme.primaryColor, AppTheme.primaryLightColor],
      Icons.photo_library_rounded,
      'Browse your VR photos',
    ),
    'Monitor': (
      [AppTheme.accentCyan, Color(0xFF8CC7F6)],
      Icons.monitor_rounded,
      'Track background activity',
    ),
    'Account': (
      [AppTheme.successColor, Color(0xFF22C55E)],
      Icons.account_circle_rounded,
      'Manage your account details',
    ),
    'Settings': (
      [AppTheme.brandPurple, AppTheme.brandPurpleDeep],
      Icons.settings_rounded,
      'Customize your GalleVR experience',
    ),
  };

  Widget _buildHeaderTitle(bool isSmallScreen) {
    final label = _navItems[_currentIndex].label;
    final section = _sectionHeaders[label];
    final fontSize = isSmallScreen ? 20.0 : 24.0;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: fontSize * -0.025,
      height: 1.2,
      color: AppTheme.textColor,
    );

    if (section == null) return Text(label, style: textStyle);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your ', style: textStyle),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback:
              (bounds) => LinearGradient(
                colors: section.$1,
              ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          child: Text(label, style: textStyle),
        ),
      ],
    );
  }

  Widget _buildHeaderSubtext() {
    final section = _sectionHeaders[_navItems[_currentIndex].label];
    if (section == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(section.$2, size: 14, color: section.$1.first),
          const SizedBox(width: 6),
          Text(
            section.$3,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectButton(PhotosState state) {
    final isSelectionMode = state.isSelectionMode;
    final color = isSelectionMode ? AppTheme.errorColor : AppTheme.brandPurple;
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _photosController.toggleSelectionMode,
        icon: Icon(
          isSelectionMode
              ? Icons.close_rounded
              : Icons.library_add_check_outlined,
          size: 18,
        ),
        label: Text(isSelectionMode ? 'Cancel' : 'Select'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.tint(color, 0.22),
          foregroundColor: Colors.white,
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: _isSidebarCollapsed ? 70 : 250,
        decoration: const BoxDecoration(
          color: AppTheme.surfaceBase,
          border: Border(right: BorderSide(color: AppTheme.cardBorderColor)),
        ),
        child: Column(
          children: [
            _buildSidebarHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
        decoration: BoxDecoration(
          color: AppTheme.surfaceBase,
          border: Border(
            top: BorderSide(color: AppTheme.cardBorderColor, width: 1),
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
                          Icon(
                            item.icon,
                            color:
                                isSelected
                                    ? AppTheme.primaryColor
                                    : item.iconColor,
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w600
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
    const double collapsedLogoSize = 48;
    const double expandedLogoSize = 70;

    return Container(
      height: 100,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorderColor, width: 1),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: _isSidebarCollapsed ? 70 : 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: _isSidebarCollapsed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: expandedLogoSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              AnimatedOpacity(
                opacity: _isSidebarCollapsed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/images/square.png',
                    height: collapsedLogoSize,
                    width: collapsedLogoSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarToggle() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.cardBorderColor, width: 1),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          onTap: _toggleSidebar,
          child: AnimatedRotation(
            turns: _isSidebarCollapsed ? 0.0 : 0.5,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: const Icon(Icons.chevron_right, size: 20),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavItems() {
    return _navItems.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isSelected = index == _currentIndex;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _selectNavItem(index),
            hoverColor: AppTheme.buttonHoverColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.buttonColor : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: isSelected ? AppTheme.primaryColor : item.iconColor,
                    size: isSelected ? 24 : 22,
                  ),
                  if (!_isSidebarCollapsed) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color:
                              isSelected
                                  ? AppTheme.textColor
                                  : AppTheme.secondaryTextColor,
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
      setState(() {
        _currentIndex = index;
        _builtTabs.add(index);
      });
      _fadeController.forward();
    });
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;
  final Color iconColor;

  _NavItem({
    required this.icon,
    required this.label,
    required this.screen,
    required this.iconColor,
  });
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;

  const _HelpButton({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: const Icon(Icons.help_outline_rounded, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        backgroundColor: AppTheme.buttonColor,
        hoverColor: AppTheme.buttonHoverColor,
        foregroundColor: AppTheme.textColor,
        side: const BorderSide(color: AppTheme.buttonBorderColor),
      ),
    );
  }
}
