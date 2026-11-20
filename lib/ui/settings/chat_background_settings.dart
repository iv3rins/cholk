import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.dart';
import '../../i18n/strings_background.dart';
import '../../models/app_settings.dart';
import '../../models/chat_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../app_scope.dart';
import '../chat/background_image.dart';
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

  /// The slider position while dragging; saved once the drag ends.
  double? _dragDim;

  Future<void> _run(Future<void> Function() action, {String? error}) async {
    final scope = AppScope.of(context);
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showToast(context, error ?? scope.strings.settingsSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _select(ChatBackground option) async {
    final controller = AppScope.of(context).controller;
    if (controller.settings.chatBackground == option &&
        controller.settings.chatBackgroundImagePath == null) {
      return;
    }
    await _run(() async {
      // Choosing a pattern means the user wants the pattern, not the picture.
      final previous = controller.settings.chatBackgroundImagePath;
      if (previous != null) {
        await controller.setChatBackgroundImage(null);
        await deleteBackgroundImage(previous);
      }
      await controller.setChatBackground(option);
    });
  }

  Future<void> _upload() async {
    final scope = AppScope.of(context);
    await _run(() async {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('Empty picture');
      final previous = scope.controller.settings.chatBackgroundImagePath;
      final path = await storeBackgroundImage(bytes, file.name);
      await scope.controller.setChatBackgroundImage(path);
      // storeBackgroundImage already cleared the folder; this covers a
      // previous picture stored elsewhere.
      if (previous != null && previous != path) {
        await deleteBackgroundImage(previous);
      }
    }, error: scope.strings.backgroundUploadFailed);
  }

  Future<void> _restoreDefault() async {
    final controller = AppScope.of(context).controller;
    await _run(() async {
      final previous = controller.settings.chatBackgroundImagePath;
      await controller.setChatBackgroundImage(null);
      await controller.setChatBackgroundDim(defaultChatBackgroundDim);
      await controller.setChatBackground(ChatBackground.plain);
      if (previous != null) await deleteBackgroundImage(previous);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final settings = scope.controller.settings;
    final imagePath = settings.chatBackgroundImagePath;
    final isDefault =
        imagePath == null &&
        settings.chatBackground == ChatBackground.plain &&
        settings.chatBackgroundDim == defaultChatBackgroundDim;
    final helperStyle = TextStyle(color: palette.textSecondary, fontSize: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.backgroundImageLabel),
        const SizedBox(height: 6),
        if (imagePath != null) ...[
          Container(
            height: 96,
            decoration: BoxDecoration(
              border: Border.all(color: palette.lineInk, width: Lineism.hair),
            ),
            child: const ChatPaper(option: ChatBackground.plain),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canUploadBackgroundImage)
              OutlinedButton.icon(
                key: const Key('background-upload'),
                onPressed: _saving ? null : _upload,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  imagePath == null
                      ? strings.uploadBackground
                      : strings.replaceBackground,
                ),
              ),
            TextButton.icon(
              key: const Key('background-restore-default'),
              onPressed: _saving || isDefault ? null : _restoreDefault,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(strings.restoreDefaultBackground),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          canUploadBackgroundImage
              ? strings.backgroundImageHint
              : strings.backgroundUploadUnsupported,
          style: helperStyle,
        ),
        if (imagePath != null) ...[
          const SizedBox(height: 10),
          Text(strings.backgroundDim),
          Slider(
            key: const Key('background-dim'),
            value: _dragDim ?? settings.chatBackgroundDim,
            divisions: 20,
            label: '${((_dragDim ?? settings.chatBackgroundDim) * 100).round()}%',
            onChanged: _saving ? null : (value) => setState(() => _dragDim = value),
            onChangeEnd: (value) async {
              await _run(() => scope.controller.setChatBackgroundDim(value));
              if (mounted) setState(() => _dragDim = null);
            },
          ),
        ],
        const SizedBox(height: 12),
        Text(strings.backgroundPatternLabel),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final option in ChatBackground.values)
              Builder(
                builder: (context) {
                  final selected =
                      imagePath == null && settings.chatBackground == option;
                  return Semantics(
                    selected: selected,
                    child: TextButton(
                      key: ValueKey('background-${option.name}'),
                      onPressed: _saving ? null : () => _select(option),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.all(6),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 32,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected
                                    ? palette.lineInk
                                    : palette.lineRule,
                                width: selected
                                    ? Lineism.emphasis
                                    : Lineism.hair,
                              ),
                            ),
                            child: ChatPaper(option: option, sample: true),
                          ),
                          const SizedBox(height: 4),
                          Text(_label(strings, option)),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
