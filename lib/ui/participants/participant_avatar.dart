import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';

class ParticipantAvatar extends StatefulWidget {
  const ParticipantAvatar({
    super.key,
    this.name,
    this.avatarBase64,
    this.size = 32,
  });

  final String? name;
  final String? avatarBase64;
  final double size;

  @override
  State<ParticipantAvatar> createState() => _ParticipantAvatarState();
}

class _ParticipantAvatarState extends State<ParticipantAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _readAvatar();
  }

  @override
  void didUpdateWidget(ParticipantAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarBase64 != widget.avatarBase64) _readAvatar();
  }

  void _readAvatar() {
    _bytes = null;
    final source = widget.avatarBase64;
    if (source == null || source.isEmpty) return;
    try {
      _bytes = base64Decode(source);
    } on FormatException {
      // Retain a readable identity if local avatar data cannot be decoded.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    final name = widget.name?.trim() ?? '';
    final initials = name.isEmpty ? '' : name.characters.take(2).toString();
    final fallback = Center(
      child: initials.isEmpty
          ? Icon(
              Icons.smart_toy_outlined,
              size: widget.size * .51,
              color: palette.lineInk2,
            )
          : Padding(
              padding: const EdgeInsets.all(3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  initials.toUpperCase(),
                  maxLines: 1,
                  style: Lineism.display.copyWith(
                    color: palette.lineInk,
                    fontSize: widget.size * .4,
                    height: 1,
                  ),
                ),
              ),
            ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: palette.lineInk, width: Lineism.base),
          ),
          child: ColoredBox(
            color: Color.alphaBlend(
              palette.accentWash,
              palette.surfaceElevated,
            ),
            child: _bytes == null
                ? fallback
                : Image.memory(
                    _bytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
