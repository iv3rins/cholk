import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import 'hanging_wordmark.dart';
import 'home_navigation.dart';
import '../chat/chat_page.dart';
import '../persona/persona_page.dart';
import '../print_kit.dart';
import '../selection_feedback.dart';
import '../settings/settings_dialog.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final overlay = palette.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: palette.background,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: HalftoneField(
                color: palette.halftone,
                origin: Alignment.topRight,
                reach: .62,
                spacing: 12,
                maxRadius: 3.4,
              ),
            ),
            Positioned.fill(
              child: HalftoneField(
                color: palette.signal.withValues(
                  alpha: palette.isDark ? .14 : .11,
                ),
                origin: Alignment.bottomLeft,
                reach: .34,
                spacing: 9,
                maxRadius: 2.4,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, size) {
                  final wide = size.maxWidth >= 680;
                  final inset = wide
                      ? (size.maxWidth * .055).clamp(32.0, 88.0)
                      : 20.0;
                  final stageHeight = (size.maxHeight * .38).clamp(
                    wide ? 190.0 : 160.0,
                    wide ? 340.0 : 268.0,
                  );
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: size.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: wide ? 18 : 8,
                                  bottom: 4,
                                ),
                                child: const _Masthead(),
                              ),
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: palette.lineInk,
                              ),
                              SizedBox(
                                width: math.min(
                                  640.0,
                                  size.maxWidth - inset * 2,
                                ),
                                height: stageHeight,
                                child: const HangingWordmark(),
                              ),
                              SizedBox(
                                height: (size.maxHeight * .055).clamp(
                                  24.0,
                                  56.0,
                                ),
                              ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: StaggeredEntrance(
                                  delay: const Duration(milliseconds: 620),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _MenuAction(
                                      label: strings.startChat,
                                      icon: Icons.east,
                                      primary: true,
                                      onPressed: () => _openMenuPage(
                                        context,
                                        const ChatPage(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _MenuAction(
                                            label: strings.persona,
                                            icon: Icons.face_outlined,
                                            onPressed: () => _openMenuPage(
                                              context,
                                              const PersonaPage(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _MenuAction(
                                            label: strings.settings,
                                            icon: Icons.tune,
                                            onPressed: () {
                                              hideCenteredNotice();
                                              showSettingsDialog(context);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: wide ? 42 : 32,
                              bottom: wide ? 16 : 8,
                            ),
                            child: const HomeNavigation(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openMenuPage(BuildContext context, Widget page) {
  hideCenteredNotice();
  final still = MediaQuery.disableAnimationsOf(context);
  Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: still
          ? Duration.zero
          : const Duration(milliseconds: 250),
      reverseTransitionDuration: still
          ? Duration.zero
          : const Duration(milliseconds: 190),
      transitionsBuilder: (_, animation, _, child) =>
          still ? child : FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = scope.palette;
    final zh = scope.strings.isZh;
    final advanced = scope.controller.settings.isAdvancedMode;
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: const Size(28, 30), painter: _ImprintPainter(p)),
            const SizedBox(width: 10),
            Text(
              zh ? '对话室' : 'Chat room',
              style: Lineism.display.copyWith(fontSize: 24, color: p.lineInk),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in [false, true])
              Semantics(
                selected: option == advanced,
                inMutuallyExclusiveGroup: true,
                child: TextButton(
                  onPressed: () async {
                    if (option == advanced) return;
                    await scope.controller.setAdvancedMode(option);
                    if (!context.mounted ||
                        ModalRoute.of(context)?.isCurrent != true) {
                      return;
                    }
                    showCenteredNotice(
                      context,
                      CenteredNotice.label(
                        dimension: zh ? '设置模式' : 'Settings mode',
                        value: option
                            ? (zh ? '进阶模式' : 'Advanced')
                            : (zh ? '普通模式' : 'Standard'),
                        zh: zh,
                      ),
                      centerInViewport: true,
                    );
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: option == advanced ? p.accent : null,
                    foregroundColor: option == advanced
                        ? p.onAccent
                        : p.lineInk,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: option == advanced ? p.signal : null,
                          border: option == advanced
                              ? null
                              : Border.all(color: p.lineInk2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        option
                            ? (zh ? '进阶模式' : 'Advanced')
                            : (zh ? '普通模式' : 'Standard'),
                        style: Lineism.display.copyWith(
                          fontSize: 15,
                          letterSpacing: .5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ImprintPainter extends CustomPainter {
  const _ImprintPainter(this.p);
  final AppPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = p.lineInk
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(2, 4), const Offset(26, 3.5), ink);
    final drum = Paint()..color = p.accent;
    final second = Paint()..color = p.signal;
    const pins = [(6.0, 16.0), (14.0, 23.0), (22.0, 12.0)];
    for (final (i, (x, y)) in pins.indexed) {
      canvas.drawLine(Offset(x, 4), Offset(x - .4, y), ink);
      final block = Rect.fromCenter(
        center: Offset(x - .4, y + 1.5),
        width: 5.5,
        height: 6,
      );
      if (i == 1) canvas.drawRect(block.shift(const Offset(1.5, 1.5)), second);
      canvas.drawRect(block, i == 1 ? drum : ink);
    }
  }

  @override
  bool shouldRepaint(_ImprintPainter oldDelegate) => oldDelegate.p != p;
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).palette;
    if (primary) {
      return PrintSlab(
        onPressed: onPressed,
        offset: const Offset(5, 5),
        padding: const EdgeInsets.fromLTRB(22, 14, 18, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Lineism.display.copyWith(
                  fontSize: 30,
                  color: p.onAccent,
                  letterSpacing: 1,
                ),
              ),
            ),
            Icon(icon, size: 26),
          ],
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 50)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered)
              ? p.accentWash
              : p.background.withValues(alpha: .82),
        ),
        foregroundColor: WidgetStatePropertyAll(p.lineInk),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.focused)
                ? p.lineSignal
                : s.contains(WidgetState.hovered)
                ? p.accent
                : p.lineInk,
            width: s.contains(WidgetState.focused) ? 2 : Lineism.base,
          ),
        ),
        overlayColor: WidgetStatePropertyAll(p.hover),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Lineism.display.copyWith(fontSize: 19, letterSpacing: .5),
            ),
          ),
        ],
      ),
    );
  }
}
