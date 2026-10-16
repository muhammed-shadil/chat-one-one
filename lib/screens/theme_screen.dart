import 'package:flutter/material.dart';

import '../services/theme_settings.dart';
import '../theme.dart';
import '../widgets/message_bubble.dart';

/// Pick the app's colors and light / dark mode. Changes apply at once.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = ThemeSettings.of(context);
    final heading = Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat theme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _Preview(),
          const SizedBox(height: 24),
          Text('Appearance', style: heading),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System')),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark')),
            ],
            selected: {settings.mode},
            onSelectionChanged: (s) => settings.mode = s.first,
          ),
          const SizedBox(height: 24),
          Text('Colors', style: heading),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final palette in kPalettes)
                  SizedBox(
                    // Three per row on phones, more on wide screens.
                    width: (constraints.maxWidth - 24) / 3 > 140
                        ? 140
                        : (constraints.maxWidth - 24) / 3,
                    child: _PaletteTile(
                      palette: palette,
                      selected: palette == settings.palette,
                      onTap: () => settings.palette = palette,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Only changes this device. The other person keeps their own theme.',
            style: TextStyle(color: ChatColors.of(context).meta, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A small chat drawn with the current theme, using the real bubbles.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final appBar = Theme.of(context).appBarTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: colors.background,
        child: Column(
          children: [
            Container(
              color: appBar.backgroundColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white24,
                    foregroundColor: appBar.foregroundColor,
                    child: const Text('A', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Text('Preview',
                      style: TextStyle(
                          color: appBar.foregroundColor,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const _PreviewBubble(text: 'Which colors do you like?', mine: false),
            const _PreviewBubble(text: 'These ones! ✨', mine: true),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return BubbleShell(
      isMine: mine,
      gapAbove: 6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(text, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text('9:41', style: TextStyle(fontSize: 11, color: colors.meta)),
          if (mine) ...[
            const SizedBox(width: 3),
            Icon(Icons.done_all, size: 15, color: colors.seen),
          ],
        ],
      ),
    );
  }
}

/// One theme to pick: a tiny chat in its colors, for the current brightness.
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ChatPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette.of(Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;

    Widget bubble(Color color, {required bool right, required double width}) =>
        Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: width,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1)],
            ),
          ),
        );

    return Semantics(
      button: true,
      selected: selected,
      label: palette.name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 96,
              decoration: BoxDecoration(
                color: p.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Container(height: 18, color: p.appBar),
                      const SizedBox(height: 6),
                      bubble(p.theirs, right: false, width: 52),
                      bubble(p.mine, right: true, width: 44),
                      bubble(p.theirs, right: false, width: 34),
                    ],
                  ),
                  if (selected)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: scheme.primary,
                        child: Icon(Icons.check, size: 15, color: scheme.onPrimary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              palette.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
