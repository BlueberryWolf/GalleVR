import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF3B82F6);
  static const Color primaryLightColor = Color(0xFF60A5FA);
  static const Color primaryDarkColor = Color(0xFF2563EB);
  static const Color secondaryColor = Color(0xFF60A5FA);

  static const Color brandPurple = Color(0xFFB884FC);
  static const Color brandPurpleStrong = Color(0xFFA855F7);
  static const Color brandPurpleDeep = Color(0xFF8B5CF6);
  static const Color switchOffColor = Color(0xFF404040);

  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentPink = Color(0xFFF472B6);
  static const Color resoniteColor = Color(0xFF00B4D8);

  static const Color backgroundColor = Color(0xFF101016);
  static const Color surfaceBase = Color(0xFF16161E);
  static const Color surfaceColor = Color(0xFF1C1C24);
  static const Color cardBackgroundColor = Color(0xFF1C1C24);
  static const Color cardHoverColor = Color(0xFF23232D);
  static const Color cardBorderColor = Color(0x14FFFFFF);
  static const Color tileColor = Color(0xFF1A1A23);

  static const Color buttonColor = Color(0xFF22222C);
  static const Color buttonHoverColor = Color(0xFF2A2A36);
  static const Color buttonBorderColor = Color(0x1AFFFFFF);

  static const Color errorColor = Color(0xFFEF4444);
  static const Color successColor = Color(0xFF4ADE80);
  static const Color warningColor = Color(0xFFF59E0B);

  static const Color textColor = Colors.white;
  static const Color secondaryTextColor = Color(0xFF9CA3AF);

  static const double radiusTag = 6;
  static const double radiusControl = 12;
  static const double radiusCard = 16;
  static const double radiusModal = 20;

  static Color tint(Color color, [double amount = 0.2]) =>
      Color.lerp(surfaceBase, color, amount)!;

  static ThemeData getLightTheme() => getDarkTheme();

  static ThemeData getDarkTheme() {
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Outfit',
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
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
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
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
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: tint(brandPurple, 0.22),
          disabledBackgroundColor: buttonColor,
          elevation: 0,
          shape: controlShape.copyWith(
            side: BorderSide(color: brandPurple.withAlpha(90)),
          ),
          padding: buttonPadding,
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
          foregroundColor: primaryLightColor,
          shape: controlShape,
          padding: buttonPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          backgroundColor: buttonColor,
          side: const BorderSide(color: buttonBorderColor),
          shape: controlShape,
          padding: buttonPadding,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: controlShape),
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
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        filled: true,
        fillColor: surfaceBase,
        hintStyle: const TextStyle(color: secondaryTextColor),
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
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textColor),
        bodyMedium: TextStyle(fontSize: 14, color: textColor),
        bodySmall: TextStyle(fontSize: 12, color: secondaryTextColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: tint(primaryColor, 0.25),
        indicatorShape: controlShape,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        backgroundColor: surfaceBase,
        elevation: 0,
        height: 70,
        iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: textColor, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceBase,
        indicatorColor: tint(primaryColor, 0.25),
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
        contentTextStyle: const TextStyle(color: textColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(radiusTag),
          border: Border.all(color: buttonBorderColor),
        ),
        textStyle: const TextStyle(color: textColor, fontSize: 12),
      ),
    );
  }
}
