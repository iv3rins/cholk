import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import 'line_studio.dart';

enum _Destination {
  about('关于', 'About'),
  project('项目', 'Project'),
  community('社区', 'Community'),
  github('GitHub', 'GitHub');

  const _Destination(this.zh, this.en);
  final String zh;
  final String en;
  String label(bool isZh) => isZh ? zh : en;
}

class HomeNavigation extends StatelessWidget {
  const HomeNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final zh = scope.strings.isZh;
    final p = scope.palette;
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: p.lineInk),
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 640;
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final destination in _Destination.values)
                  if (wide)
                    _NavLink(destination: destination, zh: zh)
                  else
                    Expanded(
                      child: _NavLink(destination: destination, zh: zh),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.destination, required this.zh});
  final _Destination destination;
  final bool zh;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).palette;
    final text = widget.destination.label(widget.zh);
    final active = _focus || _hover;
    return TextButton(
      onHover: (v) => setState(() => _hover = v),
      onFocusChange: (v) => setState(() => _focus = v),
      onPressed: () => _showDestination(context, widget.destination),
      style: TextButton.styleFrom(
        foregroundColor: p.lineInk,
        minimumSize: const Size(44, 50),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: const RoundedRectangleBorder(),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: active ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 370),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Lineism.serif.copyWith(fontSize: 15),
          ),
        ),
        builder: (_, t, child) => CustomPaint(
          foregroundPainter: _Underline(p.lineInk, t),
          child: child,
        ),
      ),
    );
  }
}

class _Underline extends CustomPainter {
  const _Underline(this.ink, this.progress);
  final Color ink;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    final w = size.width;
    final y = size.height - 1;
    final line = Path()
      ..moveTo(0, y)
      ..cubicTo(w * .21, y + 1.7, w * .62, y - 2, w, y - .4);
    final trace = line.computeMetrics().first;
    canvas.drawPath(
      trace.extractPath(0, trace.length * progress),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(_Underline oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.progress != progress;
}

void _showDestination(BuildContext context, _Destination destination) {
  final strings = AppScope.of(context).strings;
  final zh = strings.isZh;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final content = switch (destination) {
        _Destination.about => Text(
          zh ? 'Cholk 是一个支持 DeepSeek 与 OpenAI 兼容接口的对话客户端。' : 'Cholk is a chat client for DeepSeek and OpenAI-compatible services.',
        ),
        _Destination.project => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.lineStudies,
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const LineStudio(compact: true),
          ],
        ),
        _Destination.community => Text(
          zh ? '社区地址尚未公布。' : 'No community link has been published yet.',
        ),
        _Destination.github => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? 'Cholk 尚未设置公开仓库。以下是项目参考的上游仓库：' : 'No public repository is configured for Cholk. The upstream reference is:',
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () =>
                  openExternalUrl('https://github.com/deepseek-ai/chat-demo'),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('deepseek-ai/chat-demo'),
            ),
          ],
        ),
      };
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        scrollable: true,
        title: Text(destination.label(zh)),
        content: SizedBox(width: 350, child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}
