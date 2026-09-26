import 'package:flutter/material.dart';

/// A single-line label that keeps both ends visible when space is limited.
class MiddleEllipsisText extends StatelessWidget {
  const MiddleEllipsisText(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
        );
        bool fits(String value) {
          painter.text = TextSpan(text: value, style: resolvedStyle);
          painter.layout();
          return painter.width <= constraints.maxWidth;
        }

        var display = data;
        if (constraints.hasBoundedWidth && !fits(data)) {
          // Work with graphemes so CJK, emoji, and combining marks stay intact.
          final characters = data.characters.toList();
          var low = 0;
          var high = characters.length - 1;
          display = '...';
          while (low <= high) {
            final count = (low + high) ~/ 2;
            final start = (count + 1) ~/ 2;
            final end = characters.length - count ~/ 2;
            final candidate =
                '${characters.take(start).join()}...'
                '${characters.skip(end).join()}';
            if (fits(candidate)) {
              display = candidate;
              low = count + 1;
            } else {
              high = count - 1;
            }
          }
        }
        painter.dispose();
        return Text(
          display,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          semanticsLabel: data,
        );
      },
    );
  }
}
