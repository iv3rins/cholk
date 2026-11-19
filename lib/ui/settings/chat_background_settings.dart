import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.dart';
import '../../models/chat_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../app_scope.dart';
import '../chat/chat_background.dart';
import '../common.dart';
import 'settings_frame.dart';

String _label(S strings, ChatBackground option) => switch (option) {
  ChatBackground.plain => strings.backgroundPlain,
  ChatBackground.ruled => strings.backgroundRuled,
  ChatBackground.grid => strings.backgroundGrid,
  ChatBackground.dots => strings.backgroundDots,
};

Future<void> showChatBackgrounds(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final strings = AppScope.of(context).strings;
    return SettingsFrame(
      title: strings.chatBackground,
      onClose: () => Navigator.of(context).pop(),
      body: const ChatBackgroundChoices(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.done),
        ),
      ],
    );
  },
);

class ChatBackgroundChoices extends StatefulWidget {
  const ChatBackgroundChoices({super.key});

  @override
  State<ChatBackgroundChoices> createState() => _ChatBackgroundChoicesState();
}

class _ChatBackgroundChoicesState extends State<ChatBackgroundChoices> {
  bool _saving = false;

  Future<void> _select(ChatBackground option) async {
    final scope = AppScope.of(context);
    if (_saving || scope.controller.settings.chatBackground == option) return;
    setState(() => _saving = true);
    try {
      await scope.controller.setChatBackground(option);
    } catch (_) {
      if (mounted) showToast(context, scope.strings.settingsSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final option in ChatBackground.values)
          Semantics(
            selected: scope.controller.settings.chatBackground == option,
            child: TextButton(
              key: ValueKey('background-${option.name}'),
              onPressed: _saving ? null : () => _select(option),
              style: TextButton.styleFrom(padding: const EdgeInsets.all(6)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            scope.controller.settings.chatBackground == option
                            ? palette.lineInk
                            : palette.lineRule,
                        width:
                            scope.controller.settings.chatBackground == option
                            ? Lineism.emphasis
                            : Lineism.hair,
                      ),
                    ),
                    child: ChatPaper(option: option, sample: true),
                  ),
                  const SizedBox(height: 4),
                  Text(_label(scope.strings, option)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
