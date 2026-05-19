import 'package:flutter/material.dart';

import 'monitor_screen.dart';
import 'photos_screen.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/refresh_button.dart';
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
  late final List<Widget> _screens;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final PhotosController _photosController = PhotosController();
  bool _showCurlWarning = false;

  late final List<_NavItem> _navItems;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialTabIndex;
    _checkCurl();

    _navItems = [
      _NavItem(
        icon: Icons.photo_library_rounded,
        label: 'Photos',
        screen: PhotosScreen(controller: _photosController),
        iconColor: const Color(0xFFf472b6),
      ),
      _NavItem(
        icon: Icons.monitor_rounded,
        label: 'Monitor',
        screen: const MonitorScreen(),
        iconColor: const Color(0xFF22d3ee),
      ),
      _NavItem(
        icon: Icons.account_circle_rounded,
        label: 'Account',
        screen: const AccountScreen(),
        iconColor: const Color(0xFF4ade80),
      ),
      _NavItem(
        icon: Icons.settings_rounded,
        label: 'Settings',
        screen: const SettingsScreen(),
        iconColor: const Color(0xFFa8a29e),
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

    _screens = _navItems.map((item) => item.screen).toList();
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
            children: _screens,
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
        color: const Color(0xFF7c2d12).withOpacity(0.15),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFea580c).withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFf97316),
            size: 18,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'curl is not installed on your system. GalleVR will use a slower fallback uploader.',
              style: TextStyle(
                color: Color(0xFFffedd5),
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
              color: Colors.white70,
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
        color: AppTheme.surfaceColor,
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
                  return RefreshButton(
                    isLoading: state.isLoading,
                    onTap: () => _photosController.refresh(forceSync: true),
                    tooltip: 'Refresh Photos',
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderTitle(bool isSmallScreen) {
    final label = _navItems[_currentIndex].label;

    late final List<Color> gradientColors;
    late final String coloredPart;

    final textStyle = TextStyle(
      fontSize: isSmallScreen ? 20 : 24,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
      color: Colors.white,
    );

    if (label == 'Photos') {
      gradientColors = const [Color(0xFF3b82f6), Color(0xFF60a5fa)];
      coloredPart = 'Photos';
    } else if (label == 'Monitor') {
      gradientColors = const [Color(0xFF22d3ee), Color(0xFF06b6d4)];
      coloredPart = 'Monitor';
    } else if (label == 'Account') {
      gradientColors = const [Color(0xFF4ade80), Color(0xFF22c55e)];
      coloredPart = 'Account';
    } else if (label == 'Settings') {
      gradientColors = const [Color(0xFF22d3ee), Color(0xFF06b6d4)];
      coloredPart = 'Settings';
    } else {
      return Text(label, style: textStyle);
    }

    return RepaintBoundary(
      child: RichText(
        text: TextSpan(
          style: textStyle,
          children: [
            const TextSpan(text: 'Your '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: _GradientText(
                coloredPart,
                gradientColors: gradientColors,
                style: textStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSubtext() {
    final label = _navItems[_currentIndex].label;

    late final IconData subIcon;
    late final List<Color> gradientColors;
    late final String subtext;

    if (label == 'Photos') {
      subIcon = Icons.photo_library_rounded;
      gradientColors = const [Color(0xFF3b82f6), Color(0xFF60a5fa)];
      subtext = 'Browse your VR photos';
    } else if (label == 'Monitor') {
      subIcon = Icons.monitor_rounded;
      gradientColors = const [Color(0xFF22d3ee), Color(0xFF06b6d4)];
      subtext = 'Track background activity';
    } else if (label == 'Account') {
      subIcon = Icons.account_circle_rounded;
      gradientColors = const [Color(0xFF4ade80), Color(0xFF22c55e)];
      subtext = 'Manage your account details';
    } else if (label == 'Settings') {
      subIcon = Icons.settings_rounded;
      gradientColors = const [Color(0xFF22d3ee), Color(0xFF06b6d4)];
      subtext = 'Customize your GalleVR experience.';
    } else {
      return const SizedBox.shrink();
    }

    final textStyle = TextStyle(
      fontSize: 12,
      color: Colors.white.withOpacity(0.5),
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback:
                (bounds) => LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
            child: Icon(subIcon, size: 12),
          ),
          const SizedBox(width: 6),
          Text(subtext, style: textStyle),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: _isSidebarCollapsed ? 70 : 250,
        color: AppTheme.surfaceColor,
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
            Container(width: 1, color: AppTheme.cardBorderColor),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
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
                      onTap: () => _selectNavItem(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            color: item.iconColor.withOpacity(
                              isSelected ? 1.0 : 0.7,
                            ),
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              color:
                                  isSelected
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.5),
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
          borderRadius: BorderRadius.circular(12),
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
        child: InkWell(
          onTap: () => _selectNavItem(index),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? Colors.white.withOpacity(0.12)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border:
                  isSelected
                      ? Border.all(color: Colors.white.withOpacity(0.05))
                      : null,
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isSelected)
                      Positioned(
                        left: -12,
                        child: Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: item.iconColor,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: item.iconColor.withOpacity(0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    Icon(
                      item.icon,
                      color: item.iconColor.withOpacity(isSelected ? 1.0 : 0.7),
                      size: 24,
                    ),
                  ],
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color:
                            isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
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

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _HeaderActionButton({
    required this.icon,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label != null ? 12 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white.withOpacity(0.8)),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradientText extends StatelessWidget {
  const _GradientText(
    this.text, {
    required this.gradientColors,
    required this.style,
  });

  final String text;
  final TextStyle style;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback:
          (bounds) => LinearGradient(
            colors: gradientColors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}
