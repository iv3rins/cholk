import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import 'settings_frame.dart';

Future<void> showPromptEditor(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PromptEditor());

class _PromptEditor extends StatefulWidget {
  const _PromptEditor();

  @override
  State<_PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<_PromptEditor> {
  TextEditingController? _prompt;
  bool _saving = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prompt ??= TextEditingController(
      text: AppScope.of(context).controller.settings.systemPromptOverride,
    );
  }

  @override
  void dispose() {
    _prompt?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final controller = AppScope.of(context).controller;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await controller.setSystemPrompt(_prompt!.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    return PopScope(
      canPop: !_saving,
      child: SettingsFrame(
        title: strings.promptEditor,
        onClose: _saving ? null : () => Navigator.of(context).pop(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.promptEditorDescription),
            const SizedBox(height: 14),
            TextField(
              scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              key: const Key('system-prompt-text'),
              controller: _prompt,
              enabled: !_saving,
              minLines: 4,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: strings.promptEditor,
                hintText: strings.promptEditorPlaceholder,
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _saving ? null : _prompt!.clear,
              icon: const Icon(Icons.restart_alt_outlined, size: 18),
              label: Text(strings.useBuiltInPrompt),
            ),
            if (_failed)
              Semantics(
                liveRegion: true,
                child: Text(strings.settingsSaveFailed),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('system-prompt-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? strings.saving : strings.save),
          ),
        ],
      ),
    );
  }
}
