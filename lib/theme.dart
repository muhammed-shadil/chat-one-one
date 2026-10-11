import 'package:flutter/material.dart';

const _seed = Color(0xFF008069);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      primary: dark ? const Color(0xFF00A884) : _seed,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF1F2C34) : _seed,
      foregroundColor: dark ? const Color(0xFFE9EDEF) : Colors.white,
    ),
  );
}

/// Colors specific to the chat surface.
class ChatColors {
  const ChatColors._({
    required this.background,
    required this.mine,
    required this.theirs,
    required this.meta,
    required this.seen,
    required this.chip,
    required this.inputBar,
  });

  final Color background;
  final Color mine;
  final Color theirs;
  final Color meta;
  final Color seen;
  final Color chip;
  final Color inputBar;

  static ChatColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = ChatColors._(
    background: Color(0xFFEFE7DE),
    mine: Color(0xFFD9FDD3),
    theirs: Colors.white,
    meta: Color(0xFF667781),
    seen: Color(0xFF53BDEB),
    chip: Colors.white,
    inputBar: Colors.white,
  );

  static const _dark = ChatColors._(
    background: Color(0xFF0B141A),
    mine: Color(0xFF005C4B),
    theirs: Color(0xFF202C33),
    meta: Color(0xFF8696A0),
    seen: Color(0xFF53BDEB),
    chip: Color(0xFF182229),
    inputBar: Color(0xFF202C33),
  );
}
