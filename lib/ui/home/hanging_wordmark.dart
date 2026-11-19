import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';

class HangingWordmark extends StatefulWidget {
  const HangingWordmark({super.key});

  @override
  State<HangingWordmark> createState() => _HangingWordmarkState();
}

class _HangingWordmarkState extends State<HangingWordmark>
    with TickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  );
  late final _touch = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 2100),
  );
  bool _started = false;
  bool _still = false;
  double _touchX = .5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _entrance.value = _touch.value = 1;
    } else if (!_started) {
      _entrance.forward();
    }
    _started = true;
  }

  void _nudge(Offset position) {
    if (_still || _touch.isAnimating || _entrance.value < .35) return;
    final width = context.size!.width;
    if (width <= 0) return;
    setState(() => _touchX = (position.dx / width).clamp(0, 1));
    _touch.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _touch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Semantics(
      header: true,
      label: 'CHOLK',
      child: MouseRegion(
        onEnter: (event) => _nudge(event.localPosition),
        child: Listener(
          onPointerDown: (event) => _nudge(event.localPosition),
          behavior: HitTestBehavior.translucent,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WordmarkPainter(
                ink: palette.lineInk,
                thread: palette.lineInk2,
                drum: palette.accent,
                entrance: _entrance,
                touch: _touch,
                touchX: _touchX,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter({
    required this.ink,
    required this.thread,
    required this.drum,
    required this.entrance,
    required this.touch,
    required this.touchX,
  }) : super(repaint: Listenable.merge([entrance, touch]));

  final Color ink, thread, drum;
  final Animation<double> entrance, touch;
  final double touchX;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const drawingWidth = 516.0;
    final scale = math.min(size.width / 536, size.height / 198);
    final left = (size.width - drawingWidth * scale) / 2;
    final top = size.height * .94 - 128 * scale;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Lineism.hair
      ..strokeCap = StrokeCap.round
      ..color = thread;
    final print = Paint();
    for (var i = 0; i < _letters.length; i++) {
      final letter = _letters[i];
      final pinX = left + (letter.x + letter.eye.dx) * scale;
      final drop = top + (letter.level + letter.eye.dy) * scale;
      final rootX = pinX + letter.lean * scale;
      final t = entrance.value - i * .008;
      final grow = Curves.easeInOutCubic.transform((t / .34).clamp(0, 1));
      final reveal = Curves.easeOut.transform(((t - .34) / .18).clamp(0, 1));
      final release = ((t - .34) / (.66 - i * .008)).clamp(0.0, 1.0);
      final distance = (pinX / size.width - touchX).abs();
      final angle =
          _swing(release, i) * .024 * (i.isEven ? 1 : -1) +
          _swing(touch.value, i) *
              (.038 / (1 + 9 * distance)) *
              (touchX < pinX / size.width ? -1 : 1);
      final end = Offset(pinX - drop * math.sin(angle), drop * math.cos(angle));
      final root = Offset(rootX, 0);
      final control = Offset(
        (rootX + end.dx) / 2 + letter.lean * scale,
        drop * .52,
      );
      // Grow the cord along its own curve, without moving its fixed ceiling pin.
      final a = Offset.lerp(root, control, grow)!;
      final b = Offset.lerp(control, end, grow)!;
      final tip = Offset.lerp(a, b, grow)!;
      canvas.drawPath(
        Path()
          ..moveTo(root.dx, 0)
          ..quadraticBezierTo(a.dx, a.dy, tip.dx, tip.dy),
        line,
      );
      if (reveal == 0) continue;
      canvas.save();
      canvas.translate(end.dx, end.dy);
      canvas.rotate(letter.tilt + angle);
      canvas.scale(scale);
      canvas.translate(-letter.eye.dx, -letter.eye.dy);
      // Second drum, slightly off register; it settles as the letter lands.
      final slip = 5.5 + 6 * (1 - reveal);
      canvas.save();
      canvas.translate(slip * (i.isEven ? 1 : .6), slip * .8);
      canvas.drawPath(
        letter.cut,
        print..color = drum.withValues(alpha: reveal),
      );
      canvas.restore();
      canvas.drawPath(
        letter.cut,
        print
          ..color = ink.withValues(alpha: reveal)
          ..blendMode = BlendMode.srcOver,
      );
      canvas.restore();
    }
  }

  static double _swing(double t, int i) => t == 1
      ? 0
      : math.sin(t * (15.2 + i * .63)) * math.exp(-4.2 * t) * (1 - t);

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      ink != old.ink ||
      thread != old.thread ||
      drum != old.drum ||
      touchX != old.touchX ||
      entrance != old.entrance ||
      touch != old.touch;
}

// Each silhouette has its own knife-cut outline. The counters and the reversed
// H and K are holes, so the page itself shows through them in either theme.
final _letters = [
  (
    x: 0.0,
    eye: const Offset(51, 3),
    level: 5.0,
    lean: -3.0,
    tilt: -.033,
    cut: Path()
      ..moveTo(95, 22)
      ..cubicTo(80, 1, 59, -3, 39, 2)
      ..cubicTo(15, 8, 1, 29, 1, 58)
      ..cubicTo(-1, 86, 9, 105, 30, 115)
      ..cubicTo(53, 126, 80, 118, 98, 95)
      ..lineTo(73, 74)
      ..cubicTo(66, 84, 59, 89, 51, 87)
      ..cubicTo(40, 85, 36, 74, 36, 60)
      ..cubicTo(35, 43, 42, 32, 52, 31)
      ..cubicTo(60, 29, 66, 34, 71, 41)
      ..lineTo(95, 24)
      ..close(),
  ),
  (
    x: 106.0,
    eye: const Offset(45, 4),
    level: -1.0,
    lean: 4.0,
    tilt: .038,
    cut: Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(2, 9)
      ..quadraticBezierTo(23, 5, 48, 2)
      ..lineTo(50, 3)
      ..lineTo(68, 1)
      ..lineTo(96, 0)
      ..quadraticBezierTo(100, 37, 99, 56)
      ..lineTo(101, 117)
      ..quadraticBezierTo(73, 121, 45, 122)
      ..lineTo(5, 124)
      ..lineTo(4, 103)
      ..lineTo(5, 102)
      ..lineTo(3, 80)
      ..quadraticBezierTo(1, 43, 2, 9)
      ..close()
      ..moveTo(15, 20)
      ..lineTo(40, 17)
      ..lineTo(41, 50)
      ..quadraticBezierTo(52, 49, 61, 48)
      ..lineTo(60, 15)
      ..lineTo(84, 13)
      ..lineTo(87, 104)
      ..lineTo(62, 107)
      ..lineTo(61, 72)
      ..lineTo(42, 74)
      ..lineTo(43, 109)
      ..lineTo(17, 111)
      ..quadraticBezierTo(18, 67, 15, 20)
      ..close(),
  ),
  (
    x: 215.0,
    eye: const Offset(49, 3),
    level: 4.0,
    lean: -1.8,
    tilt: -.042,
    cut: Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(53, 0)
      ..cubicTo(81, -1, 102, 18, 105, 49)
      ..cubicTo(110, 83, 95, 113, 69, 120)
      ..cubicTo(42, 127, 13, 116, 4, 87)
      ..cubicTo(-5, 61, 1, 33, 15, 16)
      ..cubicTo(26, 4, 39, 1, 53, 0)
      ..close()
      ..moveTo(56, 29)
      ..cubicTo(44, 25, 36, 38, 34, 57)
      ..cubicTo(32, 77, 37, 91, 49, 93)
      ..cubicTo(61, 96, 70, 81, 72, 61)
      ..cubicTo(74, 43, 68, 31, 56, 29)
      ..close(),
  ),
  (
    x: 328.0,
    eye: const Offset(20, 3),
    level: -1.0,
    lean: 2.5,
    tilt: .021,
    cut: Path()
      ..moveTo(1, 3)
      ..quadraticBezierTo(20, 3, 39, 0)
      ..lineTo(38, 39)
      ..quadraticBezierTo(37, 66, 39, 85)
      ..quadraticBezierTo(56, 85, 77, 82)
      ..lineTo(80, 116)
      ..quadraticBezierTo(53, 120, 2, 121)
      ..lineTo(3, 93)
      ..lineTo(2, 69)
      ..lineTo(3, 55)
      ..close(),
  ),
  (
    x: 416.0,
    eye: const Offset(51, 5),
    level: 4.0,
    lean: -3.8,
    tilt: -.037,
    cut: Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(3, 2)
      ..quadraticBezierTo(26, 1, 50, 3)
      ..lineTo(74, 3)
      ..lineTo(97, 5)
      ..lineTo(98, 45)
      ..quadraticBezierTo(97, 71, 101, 117)
      ..lineTo(82, 119)
      ..lineTo(80, 118)
      ..quadraticBezierTo(40, 122, 2, 117)
      ..lineTo(1, 74)
      ..lineTo(2, 72)
      ..quadraticBezierTo(-1, 34, 3, 2)
      ..close()
      ..moveTo(15, 14)
      ..lineTo(40, 15)
      ..lineTo(39, 48)
      ..quadraticBezierTo(49, 35, 63, 15)
      ..lineTo(88, 18)
      ..lineTo(59, 58)
      ..quadraticBezierTo(71, 80, 91, 103)
      ..lineTo(63, 107)
      ..lineTo(39, 72)
      ..lineTo(40, 105)
      ..lineTo(15, 105)
      ..quadraticBezierTo(17, 60, 15, 14)
      ..close(),
  ),
];
