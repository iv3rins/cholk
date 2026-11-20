import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Native builds keep the picture as a file in the app documents directory.
const canUploadBackgroundImage = true;

/// Copies [bytes] into `<documents>/chat_background/` and returns the new
/// path. Earlier uploads in that folder are removed so only one picture stays.
Future<String> storeBackgroundImage(Uint8List bytes, String name) async {
  final documents = await getApplicationDocumentsDirectory();
  final folder = Directory(
    '${documents.path}${Platform.pathSeparator}chat_background',
  );
  await folder.create(recursive: true);
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot).toLowerCase();
  final file = File(
    '${folder.path}${Platform.pathSeparator}'
    'background-${DateTime.now().millisecondsSinceEpoch}$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  await for (final entry in folder.list()) {
    if (entry is File && entry.path != file.path) await entry.delete();
  }
  return file.path;
}

/// Deletes a stored picture; a file that is already gone is not an error.
Future<void> deleteBackgroundImage(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

class BackgroundImage extends StatelessWidget {
  const BackgroundImage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );
}
