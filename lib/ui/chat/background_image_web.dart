import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

/// The web build has no documents directory, so the upload action is hidden.
const canUploadBackgroundImage = false;

Future<String> storeBackgroundImage(Uint8List bytes, String name) =>
    throw UnsupportedError('Background pictures are not stored on the web');

Future<void> deleteBackgroundImage(String path) async {}

class BackgroundImage extends StatelessWidget {
  const BackgroundImage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
