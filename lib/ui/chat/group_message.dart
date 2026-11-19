import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';

/// Places an identity beside the existing message body, not inside its bubble.
class GroupMessage extends StatelessWidget {
  const GroupMessage({
    super.key,
    required this.avatar,
    required this.child,
    this.outgoing = false,
  });

  final Widget avatar;
  final Widget child;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Flexible(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * .84),
          child: child,
        ),
      );
      const gap = SizedBox(width: 10);
      return Row(
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: outgoing ? [content, gap, avatar] : [avatar, gap, content],
      );
    },
  );
}

class GroupBubble extends StatelessWidget {
  const GroupBubble({super.key, required this.child, this.outgoing = false});

  final Widget child;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: outgoing ? const EdgeInsets.only(right: 3, bottom: 3) : null,
      decoration: BoxDecoration(
        color: outgoing
            ? Color.alphaBlend(palette.accentWash, palette.background)
            : palette.surface,
        border: Border(
          top: BorderSide(
            color: outgoing ? palette.lineInk : palette.lineRule,
            width: Lineism.base,
          ),
          right: BorderSide(
            color: outgoing ? palette.lineInk : palette.lineRule,
            width: Lineism.base,
          ),
          bottom: BorderSide(
            color: outgoing ? palette.lineInk : palette.lineRule,
            width: Lineism.base,
          ),
          // Incoming speech keeps an inked spine on the speaker's side.
          left: BorderSide(
            color: palette.lineInk,
            width: outgoing ? Lineism.base : Lineism.hero,
          ),
        ),
        boxShadow: outgoing
            ? [BoxShadow(color: palette.accent, offset: Lineism.misprint)]
            : null,
      ),
      child: child,
    );
  }
}
