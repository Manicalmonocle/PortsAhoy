import 'package:flutter/material.dart';

/// A cold north-Atlantic palette: slate water, weathered brass, lamp amber.
class Palette {
  static const deep = Color(0xFF0E1A22);
  static const hull = Color(0xFF16262F);
  static const panel = Color(0xFF1D323D);
  static const line = Color(0xFF2C4756);
  static const brass = Color(0xFFD9A441);
  static const lamp = Color(0xFFF2C572);
  static const sea = Color(0xFF4E9AAE);
  static const moss = Color(0xFF7FB069);
  static const rust = Color(0xFFC1573F);
  static const fog = Color(0xFFB6C6CE);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.deep,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.brass,
      secondary: Palette.sea,
      surface: Palette.hull,
      error: Palette.rust,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.hull,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Palette.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Palette.line),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    ),
    dividerColor: Palette.line,
    textTheme: base.textTheme.apply(
      bodyColor: Palette.fog,
      displayColor: Colors.white,
    ),
  );
}

/// Height of the dock's content, excluding the system inset beneath it.
///
/// One source of truth: anything floating above the dock positions itself at
/// `kDockHeight + MediaQuery.viewPaddingOf(context).bottom + a margin`.
/// Hardcoding a guess is how the Collect button ended up hiding behind it.
const double kDockHeight = 58;

/// Compact number formatting for tight resource chips.
String fmt(num v) {
  final a = v.abs();
  if (a >= 100000) return '${(v / 1000).round()}k';
  if (a >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
  if (a >= 100) return v.round().toString();
  if (a >= 10) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

String fmtCoin(num v) => '${fmt(v)}c';
