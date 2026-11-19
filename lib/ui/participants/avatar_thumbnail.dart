import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

const maxAvatarFileBytes = 8 * 1024 * 1024;

/// Persist one small frame instead of the original image or an external URL.
Future<String> encodeAvatarThumbnail(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > maxAvatarFileBytes) {
    throw const FormatException('Invalid avatar size');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  // The codec takes ownership of the buffer. This also works on Web, where
  // encoded ImageDescriptor dimensions are unavailable.
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      const edge = 128;
      final scale = math.min(1.0, edge / math.max(width, height));
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const FormatException('Could not read avatar');
      }
      return base64Encode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
