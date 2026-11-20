import 'package:material_ui/material_ui.dart';

import '../../models/chat_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../app_scope.dart';
import 'background_image.dart';

class ChatPaper extends StatelessWidget {
  const ChatPaper({super.key, required this.option, this.sample = false});

  final ChatBackground option;
  final bool sample;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final imagePath = sample
        ? null
        : scope.controller.settings.chatBackgroundImagePath;
    if (imagePath != null) {
      // An uploaded picture replaces the preset; the page colour laid over it
      // at the chosen strength keeps message text readable.
      return IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackgroundImage(
                key: const Key('chat-background-image'),
                path: imagePath,
              ),
              ColoredBox(
                color: palette.background.withValues(
                  alpha: scope.controller.settings.chatBackgroundDim,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PaperRules(
            option,
            palette.lineInk.withValues(alpha: sample ? .34 : .095),
            sample ? 8 : 24,
            margin: palette.signal.withValues(alpha: sample ? .7 : .32),
            // A faint cobalt bloom gives the sheet some depth; samples stay flat.
            bloom: sample
                ? null
                : palette.accent.withValues(alpha: palette.isDark ? .10 : .06),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PaperRules extends CustomPainter {
  const _PaperRules(
    this.option,
    this.ink,
    this.spacing, {
    required this.margin,
    this.bloom,
  });

  final ChatBackground option;
  final Color ink;
  final double spacing;
  final Color margin;
  final Color? bloom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bloom = this.bloom;
    if (bloom != null) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(.9, -1),
            radius: 1.1,
            colors: [bloom, bloom.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
    if (option == ChatBackground.plain) return;
    final paint = Paint()
      ..color = ink
      ..strokeWidth = Lineism.hair;
    final inset = spacing / 2;
    if (option == ChatBackground.dots) {
      for (var y = inset; y < size.height; y += spacing) {
        for (var x = inset; x < size.width; x += spacing) {
          canvas.drawCircle(Offset(x, y), spacing < 10 ? .7 : .9, paint);
        }
      }
      return;
    }
    for (var y = inset; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (option == ChatBackground.ruled) {
      // Exercise-book margin, in the second drum.
      final x = spacing * 2.5;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = margin
          ..strokeWidth = Lineism.base,
      );
    }
    if (option == ChatBackground.grid) {
      for (var x = inset; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PaperRules old) =>
      old.option != option ||
      old.ink != ink ||
      old.spacing != spacing ||
      old.margin != margin ||
      old.bloom != bloom;
}
