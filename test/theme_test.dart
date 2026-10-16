import 'package:chat_one_one/screens/theme_screen.dart';
import 'package:chat_one_one/services/theme_settings.dart';
import 'package:chat_one_one/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG contrast ratio, from 1 (none) to 21 (black on white).
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('there are at least five themes, each with its own ID', () {
    expect(kPalettes.length, greaterThanOrEqualTo(5));
    expect(kPalettes.map((p) => p.id).toSet().length, kPalettes.length);
    expect(paletteById('nope'), kPalettes.first);
  });

  group('every theme is easy to read', () {
    for (final palette in kPalettes) {
      for (final brightness in Brightness.values) {
        test('${palette.name}, ${brightness.name}', () {
          final theme = buildTheme(brightness, palette);
          final colors = theme.extension<ChatColors>()!;
          final text = theme.colorScheme.onSurface;

          for (final (bubble, name) in [
            (colors.mine, 'my bubble'),
            (colors.theirs, 'their bubble'),
          ]) {
            // 4.5 is the WCAG AA level for normal text.
            expect(contrast(text, bubble), greaterThanOrEqualTo(4.5),
                reason: 'message text on $name');
            // Times and icons are secondary, so 3 (WCAG for large text / icons).
            expect(contrast(colors.meta, bubble), greaterThanOrEqualTo(3),
                reason: 'time on $name');
          }
          expect(contrast(colors.seen, colors.mine), greaterThanOrEqualTo(2),
              reason: 'blue ticks on my bubble');
          expect(contrast(theme.appBarTheme.foregroundColor!, theme.appBarTheme.backgroundColor!),
              greaterThanOrEqualTo(4.5),
              reason: 'header text');
          expect(contrast(colors.otherAccent, colors.theirs), greaterThanOrEqualTo(3),
              reason: "the other person's name in quotes");
          expect(contrast(colors.myAccent, colors.mine), greaterThanOrEqualTo(3),
              reason: 'my name in quotes');
          expect(contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
              greaterThanOrEqualTo(3),
              reason: 'icon on the send / record button');
        });
      }
    }
  });

  test('the chosen theme and mode are remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await ThemeSettings.load();
    expect(first.palette, kPalettes.first);
    expect(first.mode, ThemeMode.system);

    first
      ..palette = paletteById('rose')
      ..mode = ThemeMode.dark;
    final again = await ThemeSettings.load();
    expect(again.palette.id, 'rose');
    expect(again.mode, ThemeMode.dark);
  });

  testWidgets('tapping a theme or mode applies it at once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await ThemeSettings.load();
    await tester.pumpWidget(ThemeSettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(Brightness.light, settings.palette),
          darkTheme: buildTheme(Brightness.dark, settings.palette),
          themeMode: settings.mode,
          home: const ThemeScreen(),
        ),
      ),
    ));

    Color appBarColor() =>
        tester.widget<Material>(find.descendant(
            of: find.byType(AppBar), matching: find.byType(Material)).first).color!;
    expect(appBarColor(), kPalettes.first.light.appBar);

    await tester.tap(find.bySemanticsLabel('Ocean blue'));
    await tester.pumpAndSettle();
    expect(settings.palette.id, 'ocean');
    expect(appBarColor(), paletteById('ocean').light.appBar);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.mode, ThemeMode.dark);
    expect(appBarColor(), paletteById('ocean').dark.appBar);
  });
}
