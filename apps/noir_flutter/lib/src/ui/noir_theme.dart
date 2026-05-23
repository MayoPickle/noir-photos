import 'package:flutter/material.dart';

class NoirColors {
  const NoirColors._();

  static const background = Color(0xff05080d);
  static const backgroundElevated = Color(0xff080d14);
  static const panel = Color(0xff0d131c);
  static const panelSoft = Color(0xff121a25);
  static const panelHover = Color(0xff172231);
  static const line = Color(0xff263241);
  static const lineStrong = Color(0xff36465a);
  static const text = Color(0xfff4f8ff);
  static const textMuted = Color(0xff94a3b8);
  static const textSubtle = Color(0xff65758a);
  static const accent = Color(0xff1d9cff);
  static const accentSoft = Color(0xff0c3157);
  static const cyan = Color(0xff53d7ff);
  static const success = Color(0xff47d18c);
  static const warning = Color(0xffffb15f);
  static const danger = Color(0xffff6b7a);
}

class NoirRadii {
  const NoirRadii._();

  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const xlarge = 22.0;
}

class NoirTheme {
  const NoirTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      bodyColor: NoirColors.text,
      displayColor: NoirColors.text,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      scaffoldBackgroundColor: NoirColors.background,
      colorScheme: const ColorScheme.dark(
        primary: NoirColors.accent,
        onPrimary: Colors.white,
        secondary: NoirColors.cyan,
        onSecondary: NoirColors.background,
        surface: NoirColors.panel,
        onSurface: NoirColors.text,
        error: NoirColors.danger,
        onError: Colors.white,
      ),
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
        headlineLarge: textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0),
        headlineMedium: textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
        titleLarge: textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
        titleMedium: textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
        labelLarge: textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
        bodySmall: textTheme.bodySmall
            ?.copyWith(color: NoirColors.textMuted, letterSpacing: 0),
      ),
      dividerColor: NoirColors.line,
      dividerTheme: const DividerThemeData(
          color: NoirColors.line, space: 1, thickness: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: NoirColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NoirColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoirRadii.large),
          side: const BorderSide(color: NoirColors.line),
        ),
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: NoirColors.textMuted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NoirColors.panelSoft,
        labelStyle: const TextStyle(color: NoirColors.textMuted),
        hintStyle: const TextStyle(color: NoirColors.textSubtle),
        prefixIconColor: NoirColors.textMuted,
        suffixIconColor: NoirColors.textMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          borderSide: const BorderSide(color: NoirColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          borderSide: const BorderSide(color: NoirColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          borderSide: const BorderSide(color: NoirColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          borderSide: const BorderSide(color: NoirColors.danger, width: 1.4),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return NoirColors.accentSoft;
            }
            return NoirColors.panelSoft;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return NoirColors.text;
            return NoirColors.textMuted;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const BorderSide(color: NoirColors.accent);
            }
            return const BorderSide(color: NoirColors.line);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NoirRadii.medium)),
          ),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return NoirColors.line;
            return NoirColors.accent;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NoirRadii.medium)),
          ),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          foregroundColor: const WidgetStatePropertyAll(NoirColors.text),
          side: const WidgetStatePropertyAll(
              BorderSide(color: NoirColors.lineStrong)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NoirRadii.medium)),
          ),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0)),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(NoirColors.accent),
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(NoirColors.text),
          overlayColor:
              WidgetStatePropertyAll(NoirColors.accent.withValues(alpha: 0.12)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NoirRadii.small)),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return NoirColors.accent;
          return NoirColors.panelSoft;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: NoirColors.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: NoirColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoirRadii.medium),
          side: const BorderSide(color: NoirColors.line),
        ),
        textStyle: const TextStyle(color: NoirColors.text),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: NoirColors.panel,
          borderRadius: BorderRadius.circular(NoirRadii.small),
          border: Border.all(color: NoirColors.line),
        ),
        textStyle: const TextStyle(color: NoirColors.text),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: NoirColors.backgroundElevated,
        selectedItemColor: NoirColors.accent,
        unselectedItemColor: NoirColors.textMuted,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

BoxDecoration noirPanelDecoration({
  Color color = NoirColors.panel,
  Color borderColor = NoirColors.line,
  double radius = NoirRadii.large,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: 30,
        offset: const Offset(0, 20),
      ),
    ],
  );
}
