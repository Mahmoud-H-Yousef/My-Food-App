import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Circular progress ring with content in the middle.
class Ring extends StatelessWidget {
  final double value; // 0..1+, over 1 draws in the error color
  final double size;
  final double stroke;
  final Color color;
  final Widget child;
  const Ring({super.key, required this.value, this.size = 150, this.stroke = 12, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value, stroke, value > 1 ? cs.error : color, cs.surfaceContainerHighest),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value, stroke;
  final Color color, track;
  _RingPainter(this.value, this.stroke, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, 2 * pi, false, base);
    final v = value.clamp(0.0, 1.0);
    if (v > 0) canvas.drawArc(rect, -pi / 2, 2 * pi * v, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

/// Label, "x / y g" and a thin bar.
class MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;
  final String unit;
  const MacroBar({super.key, required this.label, required this.value, required this.target, required this.color, this.unit = 'g'});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.labelMedium),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: target <= 0 ? 0 : (value / target).clamp(0.0, 1.0),
          minHeight: 6,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
      ),
      const SizedBox(height: 4),
      Text('${value.round()} / ${target.round()} ${unit == 'g' ? context.tr('g') : unit}', style: t.bodySmall),
    ]);
  }
}
