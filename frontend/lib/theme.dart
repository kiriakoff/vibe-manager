import 'package:flutter/material.dart';

/// Palette mirrors the original spec: deep slate background, glassmorphism
/// cards, neon status accents.
class VibeColors {
  VibeColors._();

  static const bgTop = Color(0xFF0F172A); // slate-900
  static const bgBottom = Color(0xFF1E293B); // slate-800

  static const cardFill = Color(0x14232F48);
  static const cardBorder = Color(0x1F94A3B8);

  static const accent = Color(0xFF22D3EE); // cyan-400
  static const accent2 = Color(0xFF3B82F6); // blue-500

  static const textPrimary = Color(0xFFF1F5F9); // slate-100
  static const textSecondary = Color(0xFF94A3B8); // slate-400

  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const yellow = Color(0xFFEAB308);
  static const orange = Color(0xFFF97316);
  static const dead = Color(0xFF334155);
  static const blue = Color(0xFF3B82F6);
  static const gray = Color(0xFF64748B);
}

Color statusColor(String status) {
  switch (status) {
    case 'running':
      return VibeColors.green;
    case 'exited':
      return VibeColors.red;
    case 'restarting':
      return VibeColors.yellow;
    case 'paused':
      return VibeColors.orange;
    case 'dead':
      return VibeColors.dead;
    case 'created':
      return VibeColors.blue;
    default:
      return VibeColors.gray;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'running':
      return 'Running';
    case 'exited':
      return 'Stopped';
    case 'restarting':
      return 'Restarting';
    case 'paused':
      return 'Paused';
    case 'dead':
      return 'Dead';
    case 'created':
      return 'Created';
    default:
      return 'Not Deployed';
  }
}

class VibeTheme {
  VibeTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: VibeColors.bgTop,
      colorScheme: const ColorScheme.dark(
        primary: VibeColors.accent,
        secondary: VibeColors.accent2,
        surface: VibeColors.bgTop,
        error: VibeColors.red,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: VibeColors.textPrimary,
        displayColor: VibeColors.textPrimary,
        fontFamily: 'Inter, Roboto, sans-serif',
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintStyle: const TextStyle(color: VibeColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VibeColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VibeColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VibeColors.red, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xEE1E293B),
      ),
    );
  }
}
