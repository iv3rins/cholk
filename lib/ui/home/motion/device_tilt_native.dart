import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = EventChannel('cholk/device_tilt');

bool get supportsDeviceTilt => defaultTargetPlatform == TargetPlatform.android;

Future<Stream<Offset>?> openDeviceTilt() async {
  if (!supportsDeviceTilt) return null;
  return _channel.receiveBroadcastStream().map((reading) {
    final axes = reading as List;
    return Offset((axes[0] as num).toDouble(), (axes[1] as num).toDouble());
  });
}
