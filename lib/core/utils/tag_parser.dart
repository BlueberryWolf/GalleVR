import 'package:flutter/material.dart';

final RegExp _tagRegExp = RegExp(r'(<color[=\s][^>]*>|<\/color>)', caseSensitive: false);
final RegExp _colorValueRegExp = RegExp(r'<color[=\s]\s*"?([^">]+)"?\s*>', caseSensitive: false);
final RegExp _stripRegExp = RegExp(r'<[^>]*>');

final Map<String, List<InlineSpan>> _parseCache = {};
const int _maxCacheSize = 250;

List<InlineSpan> _getParsedSpans(String text) {
  final cached = _parseCache[text];
  if (cached != null) return cached;

  final List<InlineSpan> spans = [];
  final List<Match> matches = _tagRegExp.allMatches(text).toList();

  int lastIndex = 0;
  final List<Color?> colorStack = [null];

  for (final match in matches) {
    if (match.start > lastIndex) {
      final currentColor = colorStack.last;
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
        style: currentColor != null ? TextStyle(color: currentColor) : null,
      ));
    }

    final tag = match.group(0)!;
    if (tag.startsWith('</')) {
      if (colorStack.length > 1) {
        colorStack.removeLast();
      }
    } else {
      final valueMatch = _colorValueRegExp.firstMatch(tag);
      if (valueMatch != null) {
        final colorValue = valueMatch.group(1)!.trim().toLowerCase();
        Color? parsedColor;

        if (colorValue.startsWith('#')) {
          final hexStr = colorValue.replaceAll('#', '');
          try {
            if (hexStr.length == 6) {
              parsedColor = Color(int.parse('FF$hexStr', radix: 16));
            } else if (hexStr.length == 8) {
              parsedColor = Color(int.parse(hexStr, radix: 16));
            } else if (hexStr.length == 3) {
              final r = hexStr[0];
              final g = hexStr[1];
              final b = hexStr[2];
              parsedColor = Color(int.parse('FF$r$r$g$g$b$b', radix: 16));
            }
          } catch (_) {
            // ignore malformed hex
          }
        } else {
          const namedColors = {
            'white': Colors.white,
            'black': Colors.black,
            'gray': Colors.grey,
            'grey': Colors.grey,
            'red': Colors.red,
            'green': Colors.green,
            'blue': Colors.blue,
            'yellow': Colors.yellow,
            'cyan': Colors.cyan,
            'magenta': Colors.purpleAccent,
            'orange': Colors.orange,
            'purple': Colors.purple,
            'lime': Colors.lime,
            'pink': Colors.pink,
            'brown': Colors.brown,
            'transparent': Colors.transparent,
            'clear': Colors.transparent,
          };

          parsedColor = namedColors[colorValue];

          if (parsedColor == null) {
            if (colorValue.contains('yellow')) {
              parsedColor = Colors.yellow;
            } else if (colorValue.contains('green')) {
              parsedColor = Colors.green;
            } else if (colorValue.contains('red')) {
              parsedColor = Colors.red;
            } else if (colorValue.contains('purple')) {
              parsedColor = Colors.purple;
            } else if (colorValue.contains('cyan')) {
              parsedColor = Colors.cyan;
            } else if (colorValue.contains('orange')) {
              parsedColor = Colors.orange;
            } else if (colorValue.contains('light')) {
              parsedColor = Colors.white70;
            } else if (colorValue.contains('dark')) {
              parsedColor = Colors.black87;
            }
          }
        }

        colorStack.add(parsedColor ?? colorStack.last);
      } else {
        colorStack.add(colorStack.last);
      }
    }
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    final currentColor = colorStack.last;
    spans.add(TextSpan(
      text: text.substring(lastIndex),
      style: currentColor != null ? TextStyle(color: currentColor) : null,
    ));
  }

  if (_parseCache.length >= _maxCacheSize) {
    _parseCache.remove(_parseCache.keys.first);
  }
  _parseCache[text] = spans;

  return spans;
}

InlineSpan parseResoniteTags(String text, TextStyle baseStyle) {
  if (text.isEmpty) return TextSpan(text: '', style: baseStyle);
  if (!text.toLowerCase().contains('<color')) {
    return TextSpan(text: text, style: baseStyle);
  }
  return TextSpan(
    style: baseStyle,
    children: _getParsedSpans(text),
  );
}

/// Helper to strip tags from a string to render as plain text.
String stripResoniteTags(String text) {
  return text.replaceAll(_stripRegExp, '');
}
