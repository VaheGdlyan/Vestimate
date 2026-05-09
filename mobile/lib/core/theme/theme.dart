import 'package:flutter/material.dart';

class VestimateColors {
  // Luxury Dark Palette (HSL based)
  static const Color background = Color(0xFF0A0A0A); // HSL(0, 0%, 4%)
  static const Color surface = Color(0xFF141414);    // HSL(0, 0%, 8%)
  static const Color primary = Color(0xFFE5E5E5);    // HSL(0, 0%, 90%)
  static const Color secondary = Color(0xFF888888);  // HSL(0, 0%, 53%)
  static const Color accent = Color(0xFFD4AF37);     // Metallic Gold HSL(46, 65%, 52%)
  
  static const Color error = Color(0xFFCF6679);
  static const Color success = Color(0xFF4CAF50);
}

class VestimateSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class VestimateTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: VestimateColors.background,
      colorScheme: const ColorScheme.dark(
        primary: VestimateColors.primary,
        secondary: VestimateColors.secondary,
        surface: VestimateColors.surface,
        error: VestimateColors.error,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: VestimateColors.primary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          color: VestimateColors.primary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: VestimateColors.secondary,
        ),
      ),
    );
  }
}
