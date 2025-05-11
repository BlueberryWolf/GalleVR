import 'package:flutter/material.dart';

import 'monitor_screen.dart';
import 'photos_screen.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';

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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialTabIndex;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.value = 1.0;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  final List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.photo_library_rounded,
      label: 'Photos',
      screen: const PhotosScreen(),
    ),
    _NavItem(
      icon: Icons.monitor_rounded,
      label: 'Monitor',
      screen: const MonitorScreen(),
    ),
    _NavItem(
      icon: Icons.account_circle_rounded,
      label: 'Account',
      screen: const AccountScreen(),
    ),
    _NavItem(
      icon: Icons.settings_rounded,
      label: 'Settings',
      screen: const SettingsScreen(),
    ),
  ];

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = _isSmallScreen(context);

    return Scaffold(
      bottomNavigationBar: isSmallScreen ? _buildBottomNavBar(context) : null,
      body:
          isSmallScreen
              ? _buildMobileLayout(context)
              : _buildDesktopLayout(context),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return Container(
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
                          color: isSelected ? AppTheme.primaryColor : null,
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
                            color: isSelected ? AppTheme.primaryColor : null,
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
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            border: Border(
              bottom: BorderSide(color: AppTheme.cardBorderColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Use square logo in mobile view
              SizedBox(
                height: 40,
                width: 40,
                child: Image.asset(
                  'assets/images/square.png',
                  fit: BoxFit.contain,
                ),
              ),
              const Spacer(),
              Text(
                _navItems[_currentIndex].label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),

        Expanded(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: IndexedStack(
              index: _currentIndex,
              children: _navItems.map((item) => item.screen).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
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
            ],
          ),
        ),

        Container(width: 1, color: AppTheme.cardBorderColor),

        Expanded(
          child: Column(
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.cardBorderColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _navItems[_currentIndex].label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _navItems.map((item) => item.screen).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    const double logoHeight = 60;

    return Container(
      height: 90,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.cardBorderColor, width: 1),
        ),
      ),
      child: Stack(
        children: [
          // Logo container with centered content
          Center(
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
                      transform: Matrix4.translationValues(
                        0,
                        _isSidebarCollapsed ? -5 : 0,
                        0,
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: logoHeight,
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
                      transform: Matrix4.translationValues(
                        0,
                        _isSidebarCollapsed ? 0 : 5,
                        0,
                      ),
                      child: Image.asset(
                        'assets/images/square.png',
                        height: logoHeight,
                        width: logoHeight,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggleSidebar,
              child: AnimatedRotation(
                turns: _isSidebarCollapsed ? 0.0 : 0.5,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.chevron_right, size: 20),
              ),
            ),
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
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _selectNavItem(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? AppTheme.primaryColor.withAlpha(25)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: isSelected ? AppTheme.primaryColor : null,
                    size: 24,
                  ),

                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: _isSidebarCollapsed ? 0 : 150,
                    margin: EdgeInsets.only(left: _isSidebarCollapsed ? 0 : 16),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _isSidebarCollapsed ? 0.0 : 1.0,
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontWeight:
                                isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                            color: isSelected ? AppTheme.primaryColor : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
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
      });
      _fadeController.forward();
    });
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget screen;

  _NavItem({required this.icon, required this.label, required this.screen});
}
