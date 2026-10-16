import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Courbe d'apprentissage : taux de validation de chaque révision (0 → 100 %)
/// avec sa moyenne glissante et la ligne de seuil de validation.
class RevisionChart extends StatelessWidget {
  final List<double> values;
  final List<double> trendValues;
  final double target;
  final double height;
  final String emptyLabel;

  const RevisionChart({
    super.key,
    required this.values,
    this.trendValues = const [],
    this.target = 0.95,
    this.height = 190,
    this.emptyLabel = 'Aucune révision enregistrée pour le moment.',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (values.isEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LearningCurvePainter(
          values: values,
          trend: trendValues,
          target: target,
          lineColor: colorScheme.primary,
          trendColor: colorScheme.tertiary,
          targetColor: colorScheme.error,
          gridColor: colorScheme.outlineVariant,
          labelColor: colorScheme.outline,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}

double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

class _LearningCurvePainter extends CustomPainter {
  final List<double> values;
  final List<double> trend;
  final double target;
  final Color lineColor;
  final Color trendColor;
  final Color targetColor;
  final Color gridColor;
  final Color labelColor;
  final TextDirection textDirection;
  final TextScaler textScaler;

  const _LearningCurvePainter({
    required this.values,
    required this.trend,
    required this.target,
    required this.lineColor,
    required this.trendColor,
    required this.targetColor,
    required this.gridColor,
    required this.labelColor,
    required this.textDirection,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 10.0;
    const right = 8.0;
    const bottom = 18.0;

    final rect = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (rect.width <= 4 || rect.height <= 4) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (final level in const [0.0, 0.5, 1.0]) {
      final y = rect.bottom - rect.height * level;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      _paintLabel(canvas, '${(level * 100).round()} %', Offset(0, y - 7));
    }

    final targetY = rect.bottom - rect.height * _clamp01(target);
    _paintDashedLine(
      canvas,
      Offset(rect.left, targetY),
      Offset(rect.right, targetY),
      Paint()
        ..color = targetColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.4,
    );
    _paintLabel(
      canvas,
      'seuil ${(target * 100).round()} %',
      Offset(rect.right - 82, targetY - 15),
    );

    Offset pointAt(int index, double value) {
      final ratio = values.length <= 1 ? 0.5 : index / (values.length - 1);
      final x = rect.left + rect.width * ratio;
      final y = rect.bottom - rect.height * _clamp01(value);
      return Offset(x, y);
    }

    // Aire sous la courbe.
    final area = Path()..moveTo(pointAt(0, values.first).dx, rect.bottom);
    for (var index = 0; index < values.length; index++) {
      final point = pointAt(index, values[index]);
      area.lineTo(point.dx, point.dy);
    }
    area
      ..lineTo(pointAt(values.length - 1, values.last).dx, rect.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.02),
          ],
        ).createShader(rect),
    );

    // Moyenne glissante (courbe lissée).
    if (trend.length == values.length && trend.isNotEmpty) {
      final trendPath = Path();
      for (var index = 0; index < trend.length; index++) {
        final point = pointAt(index, trend[index]);
        if (index == 0) {
          trendPath.moveTo(point.dx, point.dy);
        } else {
          trendPath.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        trendPath,
        Paint()
          ..color = trendColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // Courbe réelle + points.
    final curve = Path();
    for (var index = 0; index < values.length; index++) {
      final point = pointAt(index, values[index]);
      if (index == 0) {
        curve.moveTo(point.dx, point.dy);
      } else {
        curve.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dotPaint = Paint()..color = lineColor;
    for (var index = 0; index < values.length; index++) {
      final point = pointAt(index, values[index]);
      canvas.drawCircle(
        point,
        values.length > 60 ? 1.6 : 3,
        dotPaint,
      );
    }
  }

  void _paintDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const dash = 6.0;
    const gap = 4.0;
    var x = start.dx;
    while (x < end.dx) {
      final next = x + dash > end.dx ? end.dx : x + dash;
      canvas.drawLine(Offset(x, start.dy), Offset(next, end.dy), paint);
      x = next + gap;
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LearningCurvePainter oldDelegate) {
    return !listEquals(oldDelegate.values, values) ||
        !listEquals(oldDelegate.trend, trend) ||
        oldDelegate.target != target ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.trendColor != trendColor;
  }
}
