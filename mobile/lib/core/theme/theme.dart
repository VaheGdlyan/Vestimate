import 'dart:ui';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// VESTIMATE DESIGN SYSTEM v3.0 — Premium Luxury Fashion AI
// Silicon Valley startup aesthetic. Dark mode first.
// Apple-level clean. Pinterest + Zara visual identity.
// ══════════════════════════════════════════════════════════════════════════════

// ── COLOR TOKENS ────────────────────────────────────────────────────────────

class V {
  // Backgrounds
  static const Color bg = Color(0xFF0A0A0A);
  static const Color bgCard = Color(0xFF111111);
  static const Color bgSurface = Color(0xFF161616);
  static const Color bgElevated = Color(0xFF1C1C1E);
  static const Color bgInput = Color(0xFF1A1A1A);
  static const Color bgSheet = Color(0xFF141414);

  // Text
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF48484A);
  static const Color textMuted = Color(0xFF3A3A3C);

  // Accent — Luxury Champagne Gold
  static const Color accent = Color(0xFFD4AF37); // Champagne Gold
  static const Color accentSoft = Color(0xFFF1E1B9); // Soft Gold
  static const Color accentGlow = Color(0xFFFFE7A0);

  // Semantic
  static const Color success = Color(0xFF2E7D32);
  static const Color danger = Color(0xFFC62828);
  static const Color warning = Color(0xFFF9A825);
  static const Color info = Color(0xFF1565C0);

  // Borders
  static const Color border = Color(0x33FFFFFF); // Subtle white
  static const Color borderLight = Color(0x1AFFFFFF);
  static const Color borderGlow = Color(0x66D4AF37); // Gold glow

  // Shimmer / Skeleton
  static const Color shimmerBase = Color(0xFF2A2A2A);
  static const Color shimmerHighlight = Color(0xFF3A3A3A);

  // Gradients
  static const List<Color> gradientSilver = [Color(0xFFE0E0E0), Color(0xFFBDBDBD)];
  static const List<Color> gradientGlass = [Color(0x33FFFFFF), Color(0x0AFFFFFF)];
  static const List<Color> gradientAccent = [Color(0xFFD4AF37), Color(0xFF8A6E2F)]; // Gold gradient
  static const List<Color> gradientDark = [Color(0xFF000000), Color(0xFF121212)];

  // ── SPACING ─────────────────────────────────────────────────────────────
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;

  // ── RADII ───────────────────────────────────────────────────────────────
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double r32 = 32;

  // ── TYPOGRAPHY ──────────────────────────────────────────────────────────
  static const String fontFamily = 'Inter';

  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily, fontSize: 28, fontWeight: FontWeight.w700,
    color: textPrimary, letterSpacing: -0.5, height: 1.2,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w600,
    color: textPrimary, letterSpacing: -0.3, height: 1.25,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w600,
    color: textPrimary, height: 1.3,
  );
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400,
    color: textPrimary, height: 1.5,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w400,
    color: textSecondary, height: 1.5,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w500,
    color: textTertiary, letterSpacing: 0.5, height: 1.4,
  );
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily, fontSize: 10, fontWeight: FontWeight.w600,
    color: textTertiary, letterSpacing: 1.5,
  );
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600,
    color: bg, letterSpacing: 0.3,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// REUSABLE PREMIUM COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════

/// Glassmorphism card — frosted glass effect
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = V.r20,
    this.blur = 20,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(V.s16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: V.gradientGlass,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? V.border.withOpacity(0.5),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Premium elevated card with subtle gradient border
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool hasBorder;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = V.r20,
    this.onTap,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: margin,
        padding: padding ?? const EdgeInsets.all(V.s16),
        decoration: BoxDecoration(
          color: V.bgCard,
          borderRadius: BorderRadius.circular(borderRadius),
          border: hasBorder ? Border.all(color: V.border, width: 0.5) : null,
        ),
        child: child,
      ),
    );
  }
}

/// Subtle tag/chip
class VTag extends StatelessWidget {
  final String text;
  final Color? color;

  const VTag(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? V.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(V.r8),
        border: Border.all(color: c.withOpacity(0.15)),
      ),
      child: Text(
        text.toUpperCase(),
        style: V.label.copyWith(color: c, fontSize: 9),
      ),
    );
  }
}

/// Section header with optional trailing
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V.s20, vertical: V.s8),
      child: Row(
        children: [
          Text(title, style: V.h3),
          const Spacer(),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Text(trailing!, style: V.bodySmall.copyWith(color: V.accentSoft)),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// THEME DATA
// ══════════════════════════════════════════════════════════════════════════════

class VestimateColors {
  static const Color background = V.bg;
  static const Color card = V.bgCard;
  static const Color surface = V.bgSurface;
  static const Color primary = V.textPrimary;
  static const Color secondary = V.textSecondary;
  static const Color accent = V.accent;
  static const Color accentGreen = V.success;
  static const Color border = V.border;
  static const Color muted = V.textMuted;
  static const Color danger = V.danger;
  static const Color success = V.success;
  static const Color input = V.bgInput;
  static const Color shimmerBase = V.shimmerBase;
  static const Color shimmerHighlight = V.shimmerHighlight;
}

class VestimateSpacing {
  static const double xxs = V.s4;
  static const double xs = V.s8;
  static const double sm = V.s12;
  static const double md = V.s16;
  static const double lg = V.s20;
  static const double xl = V.s24;
}

class VestimateRadius {
  static const double card = V.r20;
  static const double button = V.r12;
  static const double chip = V.r8;
  static const double grid = V.r12;
}

class VestimateTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: V.fontFamily,
      scaffoldBackgroundColor: V.bg,
      colorScheme: const ColorScheme.dark(
        primary: V.accent,
        secondary: V.accentSoft,
        surface: V.bgSurface,
        error: V.danger,
      ),
      textTheme: const TextTheme(
        displayLarge: V.h1,
        displayMedium: V.h2,
        displaySmall: V.h3,
        bodyLarge: V.body,
        bodyMedium: V.body,
        bodySmall: V.bodySmall,
        labelSmall: V.label,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: V.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: V.h3,
      ),
      cardTheme: CardThemeData(
        color: V.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V.r20),
          side: const BorderSide(color: V.border, width: 0.5),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: V.bgSurface,
        selectedColor: V.accent.withOpacity(0.08),
        labelStyle: V.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V.r8),
          side: const BorderSide(color: V.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: V.accent,
          foregroundColor: V.bg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          textStyle: V.button,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.r12)),
          minimumSize: const Size(44, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: V.textPrimary,
          side: const BorderSide(color: V.border),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          textStyle: V.button.copyWith(color: V.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.r12)),
          minimumSize: const Size(44, 48),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: V.accent,
        foregroundColor: V.bg,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: V.bgElevated,
        contentTextStyle: V.bodySmall.copyWith(color: V.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.r12)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: V.bgInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V.r12),
          borderSide: const BorderSide(color: V.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V.r12),
          borderSide: const BorderSide(color: V.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V.r12),
          borderSide: const BorderSide(color: V.accentSoft, width: 1),
        ),
        labelStyle: V.caption,
        hintStyle: V.bodySmall.copyWith(color: V.textMuted),
      ),
      dividerTheme: const DividerThemeData(color: V.border, thickness: 0.5),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: V.bg,
        selectedItemColor: V.accent,
        unselectedItemColor: V.textMuted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontFamily: V.fontFamily, fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontFamily: V.fontFamily, fontSize: 10, fontWeight: FontWeight.w400),
      ),
    );
  }
}
