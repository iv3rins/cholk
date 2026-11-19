import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../print_kit.dart';
import '../settings/settings_dialog.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final controller = scope.controller;
    final work = controller.chatMode == ChatMode.work;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: StaggeredEntrance(
                key: ValueKey(work),
                step: const Duration(milliseconds: 110),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      work ? strings.workWelcome : strings.welcome,
                      key: ValueKey(work),
                      textAlign: TextAlign.center,
                      style: Lineism.display.copyWith(
                        fontSize: constraints.maxWidth < 500 ? 32 : 46,
                        height: 1.2,
                        color: palette.lineInk,
                        shadows: [
                          Shadow(
                            color: palette.accent.withValues(alpha: .55),
                            offset: const Offset(2.5, 2.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 40, height: 3, color: palette.accent),
                      Container(width: 14, height: 3, color: palette.signal),
                    ],
                  ),
                  if (!controller.hasChatConnection) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('welcome-account-settings'),
                      onPressed: () => showSettingsDialog(context),
                      icon: const Icon(Icons.tune_outlined, size: 18),
                      label: Text(accountConnectionHint(strings.isZh)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
