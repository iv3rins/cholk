import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../models/chat_models.dart';

class LocalAttachmentImage extends StatelessWidget {
  const LocalAttachmentImage({
    super.key,
    required this.file,
    this.size = 64,
    this.radius = 14,
  });

  final FileAttachment file;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = file.localPath;
    Widget content;
    if (path != null && File(path).existsSync()) {
      content = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    } else {
      content = _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: scheme.onSurfaceVariant,
        size: size * 0.42,
      ),
    );
  }
}
