import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF3B82F6);
  static const Color primaryLightColor = Color(0xFF60A5FA);
  static const Color primaryDarkColor = Color(0xFF2563EB);
  static const Color secondaryColor = Color(0xFF60A5FA);

  static const Color brandPurple = Color(0xFFB884FC);
  static const Color brandPurpleLight = Color(0xFFC084FC);
  static const Color brandPurpleLighter = Color(0xFFA78BFA);
  static const Color brandPurpleStrong = Color(0xFFA855F7);
  static const Color brandPurpleDeep = Color(0xFF8B5CF6);
  static const Color brandPurpleMuted = Color(0xFF966AE8);
  static const Color brandPurpleDarker = Color(0xFF7C3AED);

  static const Color iconPhotos = Color(0xFFF472B6);
  static const Color iconGalleries = brandPurpleLighter;
  static const Color iconFeed = Color(0xFF22D3EE);
  static const Color iconFavorites = Color(0xFFF87171);
  static const Color iconWorld = Color(0xFF60A5FA);
  static const Color iconPlayers = Color(0xFF4ADE80);
  static const Color iconSettings = Color(0xFFA8A29E);

  static const Color accentCyan = iconFeed;
  static const Color accentPink = iconPhotos;
  static const Color resoniteColor = Color(0xFF00B4D8);

  static const Color backgroundColor = Color(0xFF050508);
  static const Color chromeColor = Color(0xFF101018);
  static const Color sidebarBorderColor = Color(0x40464664);
  static const Color headerBorderColor = Color(0x802B292E);
  static const Color surfaceBase = Color(0xFF16161E);
  static const Color surfaceColor = Color(0xFF1A1A24);
  static const Color cardBackgroundColor = Color(0xFF1A1A24);
  static const Color cardHoverColor = Color(0xFF21212D);
  static const Color cardBorderColor = Color(0x14FFFFFF);
  static const Color cardHoverBorderColor = Color(0x29FFFFFF);
  static const Color stripDividerColor = Color(0xFF2A2A33);
  static const Color tileColor = Color(0xFF1A1A24);

  static const Color buttonColor = Color(0xFF22222C);
  static const Color buttonHoverColor = Color(0xFF2A2A36);
  static const Color buttonBorderColor = Color(0x1AFFFFFF);
  static const Color switchOffColor = Color(0xFF292929);

  static const Color errorColor = Color(0xFFEF4444);
  static const Color errorTextColor = Color(0xFFF87171);
  static const Color successColor = Color(0xFF4ADE80);
  static const Color warningColor = Color(0xFFF59E0B);

  static const Color textColor = Colors.white;
  static const Color bodyTextColor = Color(0xFFE5E7EB);
  static const Color secondaryTextColor = Color(0xFF9CA3AF);

  static const double radiusTag = 6;
  static const double radiusControl = 12;
  static const double radiusCard = 16;
  static const double radiusModal = 20;

  static Color tint(Color color, [double amount = 0.22]) =>
      Color.lerp(surfaceBase, color, amount)!;

  static Color tintBorder(Color color, [double amount = 0.35]) =>
      Color.lerp(buttonBorderColor, color, amount)!;

  static Color cardAccentBorder(Color color, [double amount = 0.30]) =>
      Color.lerp(cardBorderColor, color, amount)!;

  static BoxDecoration get modalDecoration => BoxDecoration(
    color: cardBackgroundColor,
    borderRadius: BorderRadius.circular(radiusModal),
    border: Border.all(color: cardBorderColor),
    boxShadow: const [
      BoxShadow(
        color: Color(0xCC000000),
        blurRadius: 60,
        spreadRadius: -15,
        offset: Offset(0, 25),
      ),
    ],
  );

  static final ThemeData darkTheme = getDarkTheme();

  static ThemeData getLightTheme() => darkTheme;

  static ThemeData getDarkTheme() {
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Outfit',
      colorScheme: const ColorScheme.dark(
        primary: brandPurple,
        secondary: primaryLightColor,
        surface: surfaceColor,
        surfaceContainerLow: backgroundColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: textColor,
        onError: Colors.white,
      ),
      hoverColor: Colors.white.withAlpha(16),
      splashColor: Colors.white.withAlpha(10),
      highlightColor: Colors.transparent,
      scaffoldBackgroundColor: backgroundColor,
      dividerColor: cardBorderColor,
      dividerTheme: const DividerThemeData(
        color: cardBorderColor,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brandPurple,
        circularTrackColor: cardBorderColor,
        linearTrackColor: cardBorderColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: chromeColor,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: cardBorderColor),
        ),
        color: cardBackgroundColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.5);
            }
            return Colors.white;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tint(brandPurple, 0.14);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return tint(brandPurple, 0.30);
            }
            return tint(brandPurple, 0.22);
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const BorderSide(color: buttonBorderColor);
            }
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(color: tintBorder(brandPurple, 0.50));
            }
            return BorderSide(color: tintBorder(brandPurple, 0.35));
          }),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(controlShape),
          padding: const WidgetStatePropertyAll(buttonPadding),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: tint(brandPurple, 0.22),
          shape: controlShape,
          padding: buttonPadding,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: secondaryTextColor,
          shape: controlShape,
          padding: buttonPadding,
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return secondaryTextColor.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.hovered)) return Colors.white;
            return const Color(0xFFE0E0E0);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return buttonHoverColor;
            return buttonColor;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return const BorderSide(color: cardHoverBorderColor);
            }
            return const BorderSide(color: buttonBorderColor);
          }),
          shape: WidgetStatePropertyAll(controlShape),
          padding: const WidgetStatePropertyAll(buttonPadding),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: controlShape,
          hoverColor: buttonHoverColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: buttonBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: buttonBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xD9191923),
        hintStyle: const TextStyle(color: secondaryTextColor),
        labelStyle: const TextStyle(color: secondaryTextColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 6,
        activeTrackColor: brandPurpleStrong,
        inactiveTrackColor: Color(0x1AFFFFFF),
        disabledActiveTrackColor: Color(0x33FFFFFF),
        disabledInactiveTrackColor: Color(0x1AFFFFFF),
        thumbColor: Colors.white,
        disabledThumbColor: secondaryTextColor,
        overlayColor: Colors.transparent,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: 7,
          elevation: 2,
          pressedElevation: 4,
        ),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
        trackShape: RoundedRectSliderTrackShape(),
        showValueIndicator: ShowValueIndicator.never,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.64,
          color: textColor,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.56,
          color: textColor,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.48,
          color: textColor,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: bodyTextColor),
        bodyMedium: TextStyle(fontSize: 14, color: bodyTextColor),
        bodySmall: TextStyle(fontSize: 12, color: secondaryTextColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: buttonColor,
        indicatorShape: controlShape,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        backgroundColor: chromeColor,
        elevation: 0,
        height: 64,
        iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: textColor, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: chromeColor,
        indicatorColor: buttonColor,
        indicatorShape: controlShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBackgroundColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusModal),
          side: const BorderSide(color: cardBorderColor),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: buttonColor,
        contentTextStyle: const TextStyle(
          fontFamily: 'Outfit',
          color: textColor,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          side: const BorderSide(color: buttonBorderColor),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceBase,
          borderRadius: BorderRadius.circular(radiusTag),
          border: Border.all(color: buttonBorderColor),
        ),
        textStyle: const TextStyle(color: textColor, fontSize: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brandPurple;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: secondaryTextColor, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
