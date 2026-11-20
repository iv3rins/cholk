import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../theme/app_theme.dart';
import '../../app_scope.dart';
import '../../common.dart';
import 'device_tilt.dart';
import 'line_simulation.dart';

/// Drives a [LineSimulation] for a widget: fixed-step physics on a ticker that
/// sleeps once the lines are at rest, pointer dragging, and opt-in device tilt
/// as gravity. Motion stops while the route is covered or animations are off.
mixin LineMotion<T extends StatefulWidget> on State<T>, TickerProvider {
  /// A fresh simulation at rest; also used to reset after motion is disabled.
  LineSimulation buildSimulation();

  /// Whether a drag may start now.
  bool get linesGrabbable => true;

  late LineSimulation simulation = buildSimulation();
  final lineRepaint = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _previous = Duration.zero;
  double _accumulator = 0;
  double _quiet = 0;
  bool reducedMotion = false;
  bool _visible = false;
  bool grabbing = false;
  bool tiltOn = false;
  int _tiltRequest = 0;
  Timer? _tiltTimeout;
  StreamSubscription<Offset>? _sensor;
  Offset? _neutral;
  Offset _gravity = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasVisible = _visible;
    final wasReduced = reducedMotion;
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    _visible =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (!_visible || reducedMotion) {
      _stopTilt();
      simulation.release();
      grabbing = false;
      _ticker.stop();
      if (reducedMotion && !wasReduced) simulation = buildSimulation();
    } else if (!wasVisible || wasReduced) {
      wakeLines();
    }
  }

  @override
  void dispose() {
    _stopTilt();
    _ticker.dispose();
    lineRepaint.dispose();
    super.dispose();
  }

  void wakeLines() {
    if (reducedMotion || !_visible) return;
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
      simulation.step();
      _accumulator -= LineSimulation.timeStep;
      stepped = true;
    }
    if (stepped) lineRepaint.value++;
    _quiet = simulation.dragging || simulation.moving ? 0 : _quiet + delta;
    if (_quiet > .25) _ticker.stop();
  }

  /// Swaps in [next], carrying over the current tilt. Call inside setState
  /// unless already building.
  void replaceSimulation(LineSimulation next) {
    simulation = next..setGravity(_gravity);
    grabbing = false;
    if (_gravity != Offset.zero) wakeLines();
  }

  void _stopTilt() {
    _tiltRequest++;
    _tiltTimeout?.cancel();
    _tiltTimeout = null;
    final sensor = _sensor;
    _sensor = null;
    if (sensor != null) unawaited(sensor.cancel());
    tiltOn = false;
    _neutral = null;
    _gravity = Offset.zero;
    simulation.setGravity(Offset.zero);
  }

  void _tiltUnavailable() {
    setState(_stopTilt);
    wakeLines();
    showToast(context, AppScope.of(context).strings.tiltUnavailable);
  }

  Future<void> toggleTilt() async {
    if (tiltOn) {
      setState(_stopTilt);
      wakeLines();
      return;
    }
    setState(() => tiltOn = true);
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
          simulation.setGravity(next);
          wakeLines();
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
    if (!grabbing) return;
    simulation.release();
    setState(() => grabbing = false);
    wakeLines();
  }

  /// The opt-in switch for tilt; show it only when [supportsDeviceTilt].
  Widget lineTiltButton({Key? key, double size = 44}) {
    final scope = AppScope.of(context);
    return Semantics(
      toggled: tiltOn,
      child: AppIconButton(
        key: key,
        icon: tiltOn ? Icons.screen_rotation : Icons.screen_rotation_outlined,
        tooltip: tiltOn ? scope.strings.disableTilt : scope.strings.enableTilt,
        size: size,
        color: tiltOn ? scope.palette.lineInk : scope.palette.lineInk2,
        onPressed: reducedMotion ? null : toggleTilt,
      ),
    );
  }

  /// Wraps [child] so a drag grabs the nearest mobile node within
  /// [grabRadius] world units of the pointer and pulls it along.
  Widget lineGestures({
    required Offset Function(Offset local) toWorld,
    required double grabRadius,
    HitTestBehavior behavior = HitTestBehavior.opaque,
    required Widget child,
  }) {
    if (reducedMotion) return child;
    return MouseRegion(
      cursor: grabbing ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: behavior,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) {
          if (linesGrabbable &&
              simulation.grab(toWorld(details.localPosition), grabRadius)) {
            setState(() => grabbing = true);
            wakeLines();
          }
        },
        onPanUpdate: (details) {
          if (grabbing) simulation.move(toWorld(details.localPosition));
        },
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: child,
      ),
    );
  }
}
