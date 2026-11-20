import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import 'motion/device_tilt.dart';
import 'motion/line_motion.dart';
import 'motion/line_simulation.dart';

/// The CHOLK letters hang on cords from the top edge. The cords are the same
/// line simulation as the Project page's line studies: drag a letter or a cord
/// to pull it, and opt into device tilt to let gravity swing them.
class HangingWordmark extends StatefulWidget {
  const HangingWordmark({super.key});

  @override
  State<HangingWordmark> createState() => _HangingWordmarkState();
}

class _HangingWordmarkState extends State<HangingWordmark>
    with TickerProviderStateMixin, LineMotion<HangingWordmark> {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  )..addListener(_letGo);
  bool _started = false;
  bool _released = false;
  double _ceiling = _WordmarkSpace.restCeiling;

  @override
  LineSimulation buildSimulation() => _WordmarkSpace.simulation(_ceiling);

  @override
  bool get linesGrabbable => _entrance.value >= .35;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion) {
      _entrance.value = 1;
    } else if (!_started) {
      _entrance.forward();
    }
    _started = true;
  }

  /// Once the letters land, a small alternating push sets them swinging.
  void _letGo() {
    if (_released || reducedMotion || _entrance.value < .34) return;
    _released = true;
    for (var i = 0; i < _letters.length; i++) {
      simulation.push(
        simulation.strandBody(i),
        Offset(i.isEven ? .3 : -.3, 0),
      );
    }
    wakeLines();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Semantics(
      header: true,
      label: 'CHOLK',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final space = _WordmarkSpace(constraints.biggest);
          // The cords hang from the top edge, so their length follows the
          // stage height.
          if ((space.ceiling - _ceiling).abs() > .5) {
            _ceiling = space.ceiling;
            replaceSimulation(buildSimulation());
          }
          return Stack(
            children: [
              Positioned.fill(
                child: lineGestures(
                  toWorld: space.toWorld,
                  grabRadius: _WordmarkSpace.grabRadius,
                  // Only the letters and cords take a drag; the rest of the
                  // stage still scrolls the page.
                  behavior: HitTestBehavior.deferToChild,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('wordmark-canvas'),
                      painter: _WordmarkPainter(
                        ink: palette.lineInk,
                        thread: palette.lineInk2,
                        drum: palette.accent,
                        entrance: _entrance,
                        simulation: simulation,
                        space: space,
                        repaint: lineRepaint,
                        grabbable: () => !reducedMotion && linesGrabbable,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              if (supportsDeviceTilt && !reducedMotion)
                Positioned(
                  top: 0,
                  right: 0,
                  child: lineTiltButton(
                    key: const Key('wordmark-tilt'),
                    size: 36,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Maps the drawing (536 x 198 units, letters from y = 0) onto the stage, and
/// one simulation unit onto 100 drawing units.
class _WordmarkSpace {
  factory _WordmarkSpace(Size size) {
    final scale = math.min(size.width / 536, size.height / 198);
    return _WordmarkSpace._(
      scale,
      Offset((size.width - 516 * scale) / 2, size.height * .94 - 128 * scale),
    );
  }

  const _WordmarkSpace._(this.scale, this.origin);

  static const unit = 100.0;
  static const grabRadius = .4;
  static const restCeiling = 198 * .94 - 128;

  final double scale;
  final Offset origin;

  /// Distance from the top edge down to the letter row, in drawing units.
  double get ceiling => scale <= 0 ? restCeiling : origin.dy / scale;

  Offset toScreen(Offset world) => origin + world * (unit * scale);
  Offset toWorld(Offset screen) =>
      scale <= 0 ? Offset.zero : (screen - origin) / (unit * scale);

  static LineSimulation simulation(double ceiling) {
    const cordNodes = 6;
    Offset bezier(Offset a, Offset b, Offset c, double t) =>
        a * ((1 - t) * (1 - t)) + b * (2 * (1 - t) * t) + c * (t * t);
    return LineSimulation(
      LineFigure.strands,
      bounds: Rect.fromLTRB(-.2, -ceiling / unit, 5.36, 1.6),
      strands: [
        for (final letter in _letters)
          () {
            final eye = Offset(
              letter.x + letter.eye.dx,
              letter.level + letter.eye.dy,
            );
            final root = Offset(eye.dx + letter.lean, -ceiling);
            final control = Offset(
              (root.dx + eye.dx) / 2 + letter.lean,
              -ceiling + (ceiling + eye.dy) * .52,
            );
            final center = letter.cut.getBounds().center - letter.eye;
            final cos = math.cos(letter.tilt), sin = math.sin(letter.tilt);
            final body = Offset(
              center.dx * cos - center.dy * sin,
              center.dx * sin + center.dy * cos,
            );
            return (
              cord: [
                for (var k = 0; k < cordNodes; k++)
                  bezier(root, control, eye, k / (cordNodes - 1)) / unit,
              ],
              body: (eye + body) / unit,
            );
          }(),
      ],
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter({
    required this.ink,
    required this.thread,
    required this.drum,
    required this.entrance,
    required this.simulation,
    required this.space,
    required Listenable repaint,
    required this.grabbable,
  }) : super(repaint: Listenable.merge([entrance, repaint]));

  final Color ink, thread, drum;
  final Animation<double> entrance;
  final LineSimulation simulation;
  final _WordmarkSpace space;
  final bool Function() grabbable;

  @override
  bool hitTest(Offset position) =>
      grabbable() &&
      simulation.canGrab(space.toWorld(position), _WordmarkSpace.grabRadius);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Lineism.hair
      ..strokeCap = StrokeCap.round
      ..color = thread;
    final print = Paint();
    Offset at(int node) => space.toScreen(simulation.position(node));
    for (var i = 0; i < _letters.length; i++) {
      final letter = _letters[i];
      final start = simulation.strandStart(i);
      final body = simulation.strandBody(i);
      final eye = body - 1;
      final t = entrance.value - i * .008;
      final grow = Curves.easeInOutCubic.transform((t / .34).clamp(0, 1));
      final reveal = Curves.easeOut.transform(((t - .34) / .18).clamp(0, 1));
      if (grow == 0) continue;
      final pin = at(start);
      var cord = Path()..moveTo(pin.dx, pin.dy);
      for (var n = start + 1; n < eye; n++) {
        final p = at(n);
        final mid = Offset.lerp(p, at(n + 1), .5)!;
        cord.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      }
      final end = at(eye);
      cord.lineTo(end.dx, end.dy);
      if (grow < 1) {
        // Grow the cord along its own curve from its fixed ceiling pin.
        final metric = cord.computeMetrics().first;
        cord = metric.extractPath(0, metric.length * grow);
      }
      canvas.drawPath(cord, line);
      if (reveal == 0) continue;
      final turn =
          (simulation.position(body) - simulation.position(eye)).direction -
          (simulation.rest(body) - simulation.rest(eye)).direction;
      final angle = math.atan2(math.sin(turn), math.cos(turn));
      canvas.save();
      canvas.translate(end.dx, end.dy);
      canvas.rotate(letter.tilt + angle);
      canvas.scale(space.scale);
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

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      ink != old.ink ||
      thread != old.thread ||
      drum != old.drum ||
      entrance != old.entrance ||
      simulation != old.simulation ||
      space.scale != old.space.scale ||
      space.origin != old.space.origin;
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
