import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Dark Palette (Midnight Obsidian & Amethyst Slate)
  static const Color background = Color(0xFF0C0A17);
  static const Color surface = Color(0xFF151226);
  static const Color surfaceElevated = Color(0xFF1E1A36);
  static const Color border = Color(0xFF2E2650);
  static const Color borderHighlight = Color(0xFF4C3E82);

  // Light Palette (Porcelain & Soft Lavender)
  static const Color lightBackground = Color(0xFFF7F6FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFEFEBFB);
  static const Color lightBorder = Color(0xFFDED7F5);

  // Brand Accents (Vibrant Lilac & Amethyst)
  static const Color lilac = Color(0xFFB388FF);
  static const Color lilacDark = Color(0xFF8B5CF6);
  static const Color lilacLight = Color(0xFFD8B4FE);
  static const Color lilacDeep = Color(0xFF7C3AED);

  // Backward compatibility aliases so all existing components seamlessly adopt the lilac palette
  static const Color primary = lilac;
  static const Color mint = lilac;
  static const Color mintDark = lilacDark;
  static const Color tealAccent = lilacDeep;

  // Text Colors (Dark Mode)
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3ABD0);
  static const Color textMuted = Color(0xFF7B729A);

  // Text Colors (Light Mode)
  static const Color lightTextPrimary = Color(0xFF110E1E);
  static const Color lightTextSecondary = Color(0xFF3B3354);
  static const Color lightTextMuted = Color(0xFF5D5578);

  // Chat Bubbles
  static const Color bubbleMe = Color(0xFF7C3AED);
  static const Color bubbleOther = Color(0xFF1D1834);
  static const Color lightBubbleMe = Color(0xFF8B5CF6);
  static const Color lightBubbleOther = Color(0xFFEAE4FC);

  // Gradients
  static const LinearGradient lilacGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFA855F7), Color(0xFFB388FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bubbleGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Call Accents
  static const Color callGreen = Color(0xFF10B981);
  static const Color callRed = Color(0xFFFF3B30);

  // Context-Aware Helpers
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static bool isDarkMode(BuildContext context) => isDark(context);

  static Color bg(BuildContext context) =>
      isDark(context) ? background : lightBackground;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? surface : lightSurface;

  static Color surfaceElevatedColor(BuildContext context) =>
      isDark(context) ? surfaceElevated : lightSurfaceElevated;

  static Color borderColor(BuildContext context) =>
      isDark(context) ? border : lightBorder;

  static Color text(BuildContext context) =>
      isDark(context) ? textPrimary : lightTextPrimary;

  static Color textSec(BuildContext context) =>
      isDark(context) ? textSecondary : lightTextSecondary;

  static Color textMut(BuildContext context) =>
      isDark(context) ? textMuted : lightTextMuted;

  static Color bubbleMeColor(BuildContext context) =>
      isDark(context) ? bubbleMe : lightBubbleMe;

  static Color bubbleOtherColor(BuildContext context) =>
      isDark(context) ? bubbleOther : lightBubbleOther;

  static Color mintColor(BuildContext context) =>
      isDark(context) ? lilac : lilacDark;

  static Color primaryAccent(BuildContext context) =>
      isDark(context) ? lilac : lilacDark;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: lilac,
        secondary: lilacDark,
        surface: surface,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: lilacDark,
        secondary: lilacDeep,
        surface: lightSurface,
        onSurface: lightTextPrimary,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: lightTextPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: lightTextPrimary),
      ),
    );
  }
}
