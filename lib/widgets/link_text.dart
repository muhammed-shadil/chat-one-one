import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/format.dart';

/// Message text with web addresses that open in the browser when tapped.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  /// Each link's range in the text and the recognizer that opens it.
  var _links = <(int, int, TapGestureRecognizer)>[];

  @override
  void initState() {
    super.initState();
    _findLinks();
  }

  @override
  void didUpdateWidget(LinkText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _disposeLinks();
      _findLinks();
    }
  }

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  void _findLinks() {
    final text = widget.text;
    _links = [
      for (final (start, end) in findLinks(text))
        (
          start,
          end,
          TapGestureRecognizer()..onTap = () => _open(text.substring(start, end)),
        ),
    ];
  }

  void _disposeLinks() {
    for (final (_, _, recognizer) in _links) {
      recognizer.dispose();
    }
  }

  static void _open(String link) {
    final hasScheme = link.toLowerCase().startsWith(RegExp('https?://'));
    final uri = Uri.tryParse(hasScheme ? link : 'https://$link');
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (_links.isEmpty) return Text(text, style: widget.style);

    final dark = Theme.of(context).brightness == Brightness.dark;
    final linkStyle = TextStyle(
      color: dark ? const Color(0xFF53BDEB) : const Color(0xFF027EB5),
      decoration: TextDecoration.underline,
    );
    var last = 0;
    final spans = <InlineSpan>[];
    for (final (start, end, recognizer) in _links) {
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      spans.add(TextSpan(
        text: text.substring(start, end),
        style: linkStyle,
        recognizer: recognizer,
      ));
      last = end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
