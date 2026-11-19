import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui';

import 'package:web/web.dart' as web;

JSObject? get _deviceOrientation =>
    globalContext.getProperty<JSObject?>('DeviceOrientationEvent'.toJS);

bool get supportsDeviceTilt => _deviceOrientation != null;

Future<Stream<Offset>?> openDeviceTilt() async {
  final orientation = _deviceOrientation;
  if (orientation == null || !web.window.isSecureContext) return null;
  if (orientation.hasProperty('requestPermission'.toJS).toDart) {
    final permission = await orientation
        .callMethod<JSPromise<JSString>>('requestPermission'.toJS)
        .toDart;
    if (permission.toDart != 'granted') return null;
  }
  late final StreamController<Offset> controller;
  final listener = ((web.Event event) {
    final reading = event as web.DeviceOrientationEvent;
    final beta = reading.beta;
    final gamma = reading.gamma;
    if (beta == null || gamma == null || !beta.isFinite || !gamma.isFinite) {
      return;
    }
    final pitch = beta * math.pi / 180;
    final roll = gamma * math.pi / 180;
    final x = math.sin(roll) * math.cos(pitch);
    final y = math.sin(pitch);
    final screen = web.window.screen;
    final degrees = screen.hasProperty('orientation'.toJS).toDart
        ? screen.orientation.angle
        : (globalContext
                  .getProperty<JSNumber?>('orientation'.toJS)
                  ?.toDartDouble ??
              0);
    final angle = degrees * math.pi / 180;
    controller.add(
      Offset(
        x * math.cos(angle) - y * math.sin(angle),
        x * math.sin(angle) + y * math.cos(angle),
      ),
    );
  }).toJS;
  controller = StreamController<Offset>(
    onListen: () => web.window.addEventListener('deviceorientation', listener),
    onCancel: () =>
        web.window.removeEventListener('deviceorientation', listener),
  );
  return controller.stream;
}
