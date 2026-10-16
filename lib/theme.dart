import 'package:flutter/material.dart';

/// A color theme for the whole app, with a light and a dark version.
class ChatPalette {
  const ChatPalette({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  /// Saved in settings; never change an existing one.
  final String id;
  final String name;
  final PaletteColors light;
  final PaletteColors dark;

  PaletteColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// The colors a [ChatPalette] picks for one brightness. Everything else
/// (text, menus, buttons) is derived from [primary].
class PaletteColors {
  const PaletteColors({
    required this.primary,
    required this.appBar,
    required this.background,
    required this.mine,
    required this.theirs,
    required this.seen,
    required this.otherAccent,
  });

  final Color primary;
  final Color appBar;

  /// Behind the messages.
  final Color background;

  /// My bubbles and the other person's.
  final Color mine;
  final Color theirs;

  /// Blue ticks and played voice messages.
  final Color seen;

  /// The other person's name in reply quotes (mine use [primary]).
  final Color otherAccent;
}

/// The themes on offer, the first being the default.
const kPalettes = [
  ChatPalette(
    id: 'green',
    name: 'Classic green',
    light: PaletteColors(
      primary: Color(0xFF008069),
      appBar: Color(0xFF008069),
      background: Color(0xFFEFE7DE),
      mine: Color(0xFFD9FDD3),
      theirs: Colors.white,
      seen: Color(0xFF34A3DF),
      otherAccent: Color(0xFF8E62E0),
    ),
    dark: PaletteColors(
      primary: Color(0xFF00A884),
      appBar: Color(0xFF1F2C34),
      background: Color(0xFF0B141A),
      mine: Color(0xFF005C4B),
      theirs: Color(0xFF202C33),
      seen: Color(0xFF53BDEB),
      otherAccent: Color(0xFFA67CF0),
    ),
  ),
  ChatPalette(
    id: 'ocean',
    name: 'Ocean blue',
    light: PaletteColors(
      primary: Color(0xFF1565C0),
      appBar: Color(0xFF1565C0),
      background: Color(0xFFE4ECF5),
      mine: Color(0xFFD4E6FC),
      theirs: Colors.white,
      seen: Color(0xFF0277BD),
      otherAccent: Color(0xFFD9741F),
    ),
    dark: PaletteColors(
      primary: Color(0xFF64A8F0),
      appBar: Color(0xFF17212C),
      background: Color(0xFF0A1119),
      mine: Color(0xFF1D4A7C),
      theirs: Color(0xFF1C2733),
      seen: Color(0xFF7FD8FF),
      otherAccent: Color(0xFFF2A65A),
    ),
  ),
  ChatPalette(
    id: 'lavender',
    name: 'Lavender',
    light: PaletteColors(
      primary: Color(0xFF6A4BC4),
      appBar: Color(0xFF6A4BC4),
      background: Color(0xFFEFEBF7),
      mine: Color(0xFFE5DCFF),
      theirs: Colors.white,
      seen: Color(0xFF1E88E5),
      otherAccent: Color(0xFF00897B),
    ),
    dark: PaletteColors(
      primary: Color(0xFFB39DFF),
      appBar: Color(0xFF221C30),
      background: Color(0xFF120E1A),
      mine: Color(0xFF47338C),
      theirs: Color(0xFF241E31),
      seen: Color(0xFF7FD3FF),
      otherAccent: Color(0xFF4DD0C0),
    ),
  ),
  ChatPalette(
    id: 'rose',
    name: 'Rose',
    light: PaletteColors(
      primary: Color(0xFFC2185B),
      appBar: Color(0xFFC2185B),
      background: Color(0xFFF8EAEF),
      mine: Color(0xFFFFDAE7),
      theirs: Colors.white,
      seen: Color(0xFF1E88E5),
      otherAccent: Color(0xFF5E5CE6),
    ),
    dark: PaletteColors(
      primary: Color(0xFFFF80B0),
      appBar: Color(0xFF2A1A21),
      background: Color(0xFF170D11),
      mine: Color(0xFF762047),
      theirs: Color(0xFF2A1E23),
      seen: Color(0xFF7FD3FF),
      otherAccent: Color(0xFF9E9CFF),
    ),
  ),
  ChatPalette(
    id: 'sunset',
    name: 'Sunset',
    light: PaletteColors(
      primary: Color(0xFFD84315),
      appBar: Color(0xFFBF360C),
      background: Color(0xFFF7EEE5),
      mine: Color(0xFFFFE1CD),
      theirs: Colors.white,
      seen: Color(0xFF1E88E5),
      otherAccent: Color(0xFF1B7FB8),
    ),
    dark: PaletteColors(
      primary: Color(0xFFFF8A50),
      appBar: Color(0xFF2B1D16),
      background: Color(0xFF16100C),
      mine: Color(0xFF773416),
      theirs: Color(0xFF2A211B),
      seen: Color(0xFF7FD3FF),
      otherAccent: Color(0xFF5CC3F0),
    ),
  ),
  ChatPalette(
    id: 'midnight',
    name: 'Midnight',
    light: PaletteColors(
      primary: Color(0xFF37474F),
      appBar: Color(0xFF263238),
      background: Color(0xFFE8EBED),
      mine: Color(0xFFDCE5EA),
      theirs: Colors.white,
      seen: Color(0xFF1E88E5),
      otherAccent: Color(0xFFB7791F),
    ),
    dark: PaletteColors(
      primary: Color(0xFF80CBC4),
      appBar: Color(0xFF161B1F),
      background: Color(0xFF0C1013),
      mine: Color(0xFF2E4450),
      theirs: Color(0xFF1D252A),
      seen: Color(0xFF64D8CB),
      otherAccent: Color(0xFFF0C060),
    ),
  ),
];

ChatPalette paletteById(String? id) =>
    kPalettes.firstWhere((p) => p.id == id, orElse: () => kPalettes.first);

ThemeData buildTheme(Brightness brightness, ChatPalette palette) {
  final dark = brightness == Brightness.dark;
  final p = palette.of(brightness);
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.light.primary,
      brightness: brightness,
      primary: p.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.appBar,
      foregroundColor: dark ? const Color(0xFFE9EDEF) : Colors.white,
    ),
    extensions: [ChatColors.from(p, brightness)],
  );
}

/// Colors specific to the chat surface, from the chosen [ChatPalette].
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.background,
    required this.mine,
    required this.theirs,
    required this.meta,
    required this.seen,
    required this.chip,
    required this.inputBar,
    required this.myAccent,
    required this.otherAccent,
  });

  factory ChatColors.from(PaletteColors p, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ChatColors(
      background: p.background,
      mine: p.mine,
      theirs: p.theirs,
      meta: dark ? const Color(0xFFA3B1B9) : const Color(0xFF667781),
      seen: p.seen,
      // Date separators: a step between the background and the bubbles.
      chip: dark ? Color.lerp(p.background, p.theirs, 0.6)! : Colors.white,
      inputBar: p.theirs,
      // In dark mode my bubble is a deep shade of the primary color, so my
      // name in quotes needs a lighter one to stand out on it.
      myAccent: dark ? Color.lerp(p.primary, Colors.white, 0.35)! : p.primary,
      otherAccent: p.otherAccent,
    );
  }

  final Color background;
  final Color mine;
  final Color theirs;
  final Color meta;
  final Color seen;
  final Color chip;
  final Color inputBar;

  /// Names in reply quotes: mine, and the other person's.
  final Color myAccent;
  final Color otherAccent;

  static ChatColors of(BuildContext context) =>
      Theme.of(context).extension<ChatColors>()!;

  @override
  ChatColors copyWith({
    Color? background,
    Color? mine,
    Color? theirs,
    Color? meta,
    Color? seen,
    Color? chip,
    Color? inputBar,
    Color? myAccent,
    Color? otherAccent,
  }) =>
      ChatColors(
        background: background ?? this.background,
        mine: mine ?? this.mine,
        theirs: theirs ?? this.theirs,
        meta: meta ?? this.meta,
        seen: seen ?? this.seen,
        chip: chip ?? this.chip,
        inputBar: inputBar ?? this.inputBar,
        myAccent: myAccent ?? this.myAccent,
        otherAccent: otherAccent ?? this.otherAccent,
      );

  /// Lets a theme change fade smoothly instead of jumping.
  @override
  ChatColors lerp(ChatColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChatColors(
      background: mix(background, other.background),
      mine: mix(mine, other.mine),
      theirs: mix(theirs, other.theirs),
      meta: mix(meta, other.meta),
      seen: mix(seen, other.seen),
      chip: mix(chip, other.chip),
      inputBar: mix(inputBar, other.inputBar),
      myAccent: mix(myAccent, other.myAccent),
      otherAccent: mix(otherAccent, other.otherAccent),
    );
  }
}
