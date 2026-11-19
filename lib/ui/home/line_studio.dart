import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import 'motion/device_tilt.dart';
import 'motion/line_simulation.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';

class LineStudio extends StatefulWidget {
  const LineStudio({super.key, required this.compact});

  final bool compact;

  @override
  State<LineStudio> createState() => _LineStudioState();
}

class _LineStudioState extends State<LineStudio>
    with SingleTickerProviderStateMixin {
  LineSimulation _simulation = LineSimulation(LineFigure.coil);
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _previous = Duration.zero;
  double _accumulator = 0;
  double _quiet = 0;
  bool _reduced = false;
  bool _visible = false;
  bool _grabbing = false;
  bool _tiltOn = false;
  int _tiltRequest = 0;
  Timer? _tiltTimeout;
  StreamSubscription<Offset>? _sensor;
  Offset? _neutral;
  Offset _gravity = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasVisible = _visible;
    final wasReduced = _reduced;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _visible =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (!_visible || _reduced) {
      _stopTilt();
      _simulation.release();
      _grabbing = false;
      _ticker.stop();
      if (_reduced && !wasReduced) {
        _simulation = LineSimulation(_simulation.figure);
      }
    } else if (!wasVisible || wasReduced) {
      _wake();
    }
  }

  @override
  void dispose() {
    _stopTilt();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _wake() {
    if (_reduced || !_visible) return;
    _quiet = 0;
    if (_ticker.isActive) return;
    _previous = Duration.zero;
    _accumulator = 0;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    // Bound catch-up after a resize, a missed frame, or a resumed tab.
    final delta = (elapsed - _previous).inMicroseconds / 1000000;
    _previous = elapsed;
    _accumulator += delta.clamp(0, .05);
    var stepped = false;
    while (_accumulator >= LineSimulation.timeStep) {
      _simulation.step();
      _accumulator -= LineSimulation.timeStep;
      stepped = true;
    }
    if (stepped) _repaint.value++;
    _quiet = _simulation.dragging || _simulation.moving ? 0 : _quiet + delta;
    if (_quiet > .25) _ticker.stop();
  }

  void _changeFigure(LineFigure figure) {
    if (_simulation.figure == figure) return;
    setState(() {
      _simulation = LineSimulation(figure)..setGravity(_gravity);
      _grabbing = false;
    });
    if (_gravity != Offset.zero) _wake();
  }

  void _stopTilt() {
    _tiltRequest++;
    _tiltTimeout?.cancel();
    _tiltTimeout = null;
    final sensor = _sensor;
    _sensor = null;
    if (sensor != null) unawaited(sensor.cancel());
    _tiltOn = false;
    _neutral = null;
    _gravity = Offset.zero;
    _simulation.setGravity(Offset.zero);
  }

  void _tiltUnavailable() {
    setState(_stopTilt);
    _wake();
    showToast(context, AppScope.of(context).strings.tiltUnavailable);
  }

  Future<void> _toggleTilt() async {
    if (_tiltOn) {
      setState(_stopTilt);
      _wake();
      return;
    }
    setState(() => _tiltOn = true);
    final request = ++_tiltRequest;
    try {
      final stream = await openDeviceTilt();
      if (!mounted || request != _tiltRequest) return;
      if (stream == null) {
        _tiltUnavailable();
        return;
      }
      _tiltTimeout = Timer(const Duration(seconds: 2), () {
        if (mounted && request == _tiltRequest) _tiltUnavailable();
      });
      _sensor = stream.listen(
        (axes) {
          if (!mounted || request != _tiltRequest || !axes.isFinite) return;
          _tiltTimeout?.cancel();
          final neutral = _neutral ??= axes;
          final change = axes - neutral;
          final target =
              Offset(change.dx.clamp(-.85, .85), change.dy.clamp(-.85, .85)) *
              14;
          final next = Offset.lerp(_gravity, target, .22)!;
          if ((next - _gravity).distanceSquared < .0064) return;
          _gravity = next;
          _simulation.setGravity(next);
          _wake();
        },
        onError: (Object error) {
          if (mounted && request == _tiltRequest) _tiltUnavailable();
        },
      );
    } catch (_) {
      if (mounted && request == _tiltRequest) _tiltUnavailable();
    }
  }

  void _release() {
    if (!_grabbing) return;
    _simulation.release();
    setState(() => _grabbing = false);
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final palette = scope.palette;
    final figure = _simulation.figure;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 392),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _FigureTab(
                label: strings.coil,
                selected: figure == LineFigure.coil,
                onPressed: () => _changeFigure(LineFigure.coil),
              ),
              _FigureTab(
                label: strings.web,
                selected: figure == LineFigure.web,
                onPressed: () => _changeFigure(LineFigure.web),
              ),
              const Spacer(),
              if (supportsDeviceTilt)
                Semantics(
                  toggled: _tiltOn,
                  child: AppIconButton(
                    key: const Key('line-studio-tilt'),
                    icon: _tiltOn
                        ? Icons.screen_rotation
                        : Icons.screen_rotation_outlined,
                    tooltip: _tiltOn ? strings.disableTilt : strings.enableTilt,
                    size: 44,
                    color: _tiltOn ? palette.lineInk : palette.lineInk2,
                    onPressed: _reduced ? null : _toggleTilt,
                  ),
                ),
              AppIconButton(
                key: const Key('line-studio-tug'),
                icon: Icons.gesture_outlined,
                tooltip: strings.tugLines,
                size: 44,
                onPressed: _reduced
                    ? null
                    : () {
                        _simulation.tug();
                        _wake();
                      },
              ),
            ],
          ),
          Divider(height: 1, color: palette.lineRule),
          SizedBox(
            height: widget.compact ? 150 : 184,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final space = _DrawingSpace(constraints.biggest);
                final drawing = RepaintBoundary(
                  child: CustomPaint(
                    key: const Key('line-studio-canvas'),
                    painter: _LineDrawing(_simulation, palette, _repaint),
                    child: const SizedBox.expand(),
                  ),
                );
                return Semantics(
                  image: true,
                  label: _reduced ? strings.lineStudies : strings.dragLines,
                  child: _reduced
                      ? drawing
                      : MouseRegion(
                          cursor: _grabbing
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            dragStartBehavior: DragStartBehavior.down,
                            onPanStart: (details) {
                              if (_simulation.grab(
                                space.toWorld(details.localPosition),
                                24 / space.scale,
                              )) {
                                setState(() => _grabbing = true);
                                _wake();
                              }
                            },
                            onPanUpdate: (details) {
                              if (_grabbing) {
                                _simulation.move(
                                  space.toWorld(details.localPosition),
                                );
                              }
                            },
                            onPanEnd: (_) => _release(),
                            onPanCancel: _release,
                            child: drawing,
                          ),
                        ),
                );
              },
            ),
          ),
          Divider(height: 1, color: palette.lineRule),
        ],
      ),
    );
  }
}

class _FigureTab extends StatelessWidget {
  const _FigureTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? palette.lineInk : Colors.transparent,
              width: Lineism.base,
            ),
          ),
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(56, 44),
            foregroundColor: selected ? palette.lineInk : palette.lineInk2,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _DrawingSpace {
  _DrawingSpace(this.size)
    : center = size.center(Offset.zero),
      scale = math.min(size.width / 9.6, size.height / 6.9);

  final Size size;
  final Offset center;
  final double scale;

  Offset toScreen(Offset point) => center + point * scale;
  Offset toWorld(Offset point) =>
      scale == 0 ? Offset.zero : (point - center) / scale;
}

class _LineDrawing extends CustomPainter {
  _LineDrawing(this.simulation, this.palette, Listenable repaint)
    : super(repaint: repaint);

  final LineSimulation simulation;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final space = _DrawingSpace(size);
    final guide = Paint()
      ..color = palette.lineRule
      ..strokeWidth = Lineism.hair;
    final line = Paint()
      ..color = palette.lineInk
      ..strokeWidth = Lineism.base
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Offset at(int index) => space.toScreen(simulation.position(index));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawGuides(canvas, space, guide);
    if (simulation.figure == LineFigure.coil) {
      final first = at(0);
      _cross(canvas, first, guide);
      final path = Path()..moveTo(first.dx, first.dy);
      for (var i = 1; i < LineSimulation.coilNodes - 1; i++) {
        final p = at(i);
        final mid = Offset.lerp(p, at(i + 1), .5)!;
        path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      }
      final tip = at(simulation.focusNode);
      path.lineTo(tip.dx, tip.dy);
      canvas.drawPath(path, line);
    } else {
      final center = at(0);
      const spokes = LineSimulation.webSpokes;
      const rings = LineSimulation.webRings;
      for (var spoke = 0; spoke < spokes; spoke++) {
        final path = Path()..moveTo(center.dx, center.dy);
        for (var ring = 0; ring <= rings; ring++) {
          final p = at(LineSimulation.webNode(ring, spoke));
          path.lineTo(p.dx, p.dy);
          if (ring == rings) _cross(canvas, p, guide);
        }
        canvas.drawPath(path, line);
      }
      for (var ring = 0; ring < rings; ring++) {
        final first = at(LineSimulation.webNode(ring, 0));
        final path = Path()..moveTo(first.dx, first.dy);
        for (var spoke = 0; spoke < spokes; spoke++) {
          final a = at(LineSimulation.webNode(ring, spoke));
          final b = at(LineSimulation.webNode(ring, spoke + 1));
          final control = Offset.lerp((a + b) / 2, center, .11)!;
          path.quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
        }
        canvas.drawPath(path, line);
      }
    }
    final handle = at(simulation.grabbedNode ?? simulation.focusNode);
    canvas.drawCircle(handle, 4.1, Paint()..color = palette.linePaper);
    canvas.drawCircle(handle, 3.1, Paint()..color = palette.lineSignal);
    canvas.restore();
  }

  void _drawGuides(Canvas canvas, _DrawingSpace space, Paint guide) {
    final center = space.center;
    const step = 12.0;
    for (var x = center.dx % step; x < space.size.width; x += step) {
      canvas.drawLine(Offset(x, center.dy), Offset(x + 3, center.dy), guide);
    }
    for (var y = center.dy % step; y < space.size.height; y += step) {
      canvas.drawLine(Offset(center.dx, y), Offset(center.dx, y + 3), guide);
    }
    for (final x in [-4.1, 4.1]) {
      for (final y in [-2.65, 2.65]) {
        _cross(canvas, space.toScreen(Offset(x, y)), guide);
      }
    }
  }

  void _cross(Canvas canvas, Offset at, Paint guide) {
    canvas.drawLine(at - const Offset(4, 0), at + const Offset(4, 0), guide);
    canvas.drawLine(at - const Offset(0, 4), at + const Offset(0, 4), guide);
  }

  @override
  bool shouldRepaint(_LineDrawing old) =>
      old.simulation != simulation || old.palette != palette;
}
