import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeSeed {
  const AppThemeSeed({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;
}

class AppTheme {
  // Primary colors - 专业蓝绿色调
  static const Color primaryLight = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF90CAF9);
  static const Color secondaryLight = Color(0xFF00897B);
  static const Color secondaryDark = Color(0xFF80CBC4);
  static const Color tertiaryLight = Color(0xFF7B1FA2);
  static const Color tertiaryDark = Color(0xFFCE93D8);

  // Background colors
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Text colors
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  // Accent colors for different content types
  static const Color videoColor = Color(0xFFE53935);
  static const Color conceptColor = Color(0xFF1E88E5);
  static const Color formulaColor = Color(0xFF43A047);
  static const Color referenceColor = Color(0xFFFB8C00);

  static const List<AppThemeSeed> themeSeeds = [
    AppThemeSeed(id: 'biostat', name: '生统蓝', color: primaryLight),
    AppThemeSeed(id: 'teal', name: '湖青', color: Color(0xFF00897B)),
    AppThemeSeed(id: 'indigo', name: '靛蓝', color: Color(0xFF3949AB)),
    AppThemeSeed(id: 'green', name: '森林绿', color: Color(0xFF2E7D32)),
    AppThemeSeed(id: 'rose', name: '玫瑰', color: Color(0xFFC2185B)),
    AppThemeSeed(id: 'amber', name: '琥珀', color: Color(0xFFF9A825)),
  ];

  static Color seedColorFor(String id) {
    return themeSeeds
        .firstWhere(
          (seed) => seed.id == id,
          orElse: () => themeSeeds.first,
        )
        .color;
  }

  static ThemeData lightTheme = buildLightTheme();
  static ThemeData darkTheme = buildDarkTheme();

  static ThemeData buildLightTheme({Color seedColor = primaryLight}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundLight,
      surfaceColor: surfaceLight,
      textPrimary: textPrimaryLight,
      inputFillColor: Colors.grey[100]!,
      cardElevation: 2,
    );
  }

  static ThemeData buildDarkTheme({
    Color seedColor = primaryLight,
    bool amoled = false,
  }) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    final colorScheme = amoled
        ? baseScheme.copyWith(
            surface: Colors.black,
            onSurface: textPrimaryDark,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF050505),
            surfaceContainer: const Color(0xFF080808),
            surfaceContainerHigh: const Color(0xFF0D0D0D),
            surfaceContainerHighest: const Color(0xFF121212),
          )
        : baseScheme;
    final surface = amoled ? Colors.black : surfaceDark;
    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: amoled ? Colors.black : backgroundDark,
      surfaceColor: surface,
      textPrimary: textPrimaryDark,
      inputFillColor: amoled ? const Color(0xFF090909) : Colors.grey[900]!,
      cardElevation: amoled ? 0 : 4,
      amoled: amoled,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color surfaceColor,
    required Color textPrimary,
    required Color inputFillColor,
    required double cardElevation,
    bool amoled = false,
  }) {
    final textTheme = colorScheme.brightness == Brightness.dark
        ? GoogleFonts.notoSansScTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.notoSansScTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: amoled ? Colors.black : surfaceColor,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        color: surfaceColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.notoSansSc(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.notoSansSc(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 8,
        backgroundColor: surfaceColor,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.notoSansSc(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
      ),
    );
  }
}
