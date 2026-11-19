import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/persona.dart';
import '../../theme/app_theme.dart';

/// Opens the persona editor.
///
/// Completes with the saved persona when the user saves, or with `null` when
/// the editor is dismissed. Editing a built-in persona saves a custom copy and
/// returns that copy; the built-in entry itself is never modified.
Future<Persona?> openPersonaEditor(BuildContext context, {Persona? persona}) =>
    Navigator.of(context).push<Persona>(
      MaterialPageRoute<Persona>(
        builder: (_) => PersonaEditorPage(persona: persona),
      ),
    );

class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, this.persona});

  /// The persona to edit, or `null` to create a new one.
  final Persona? persona;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _workflow;
  bool _initialised = false;
  bool _saving = false;
  bool _saveError = false;

  /// Built-in personas are copied rather than modified, and their fields start
  /// from the English copy so the editor never shows a blank or mixed preset.
  bool get _isBuiltInCopy =>
      widget.persona != null && !widget.persona!.isCustom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final persona = widget.persona;
    // Built-ins always open in English; custom personas follow the UI language.
    final english = _isBuiltInCopy || !(AppScope.of(context).strings.isZh);
    final String initialName;
    if (persona == null) {
      initialName = '';
    } else if (english) {
      initialName = persona.nameEn;
    } else {
      initialName = persona.nameZh;
    }
    final String initialPrompt;
    if (persona == null) {
      initialPrompt = '';
    } else if (english) {
      initialPrompt = persona.promptEn ?? '';
    } else {
      initialPrompt = persona.promptZh ?? '';
    }
    _name = TextEditingController(text: initialName);
    _prompt = TextEditingController(text: initialPrompt);
    _workflow = TextEditingController(
      text: persona == null ? '' : persona.workflow.join('\n'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _workflow.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _saveError = false;
    });
    try {
      final saved = await scope.controller.savePersona(
        // A built-in id would be rejected: editing one always creates a copy.
        id: _isBuiltInCopy ? null : widget.persona?.id,
        name: _name.text.trim(),
        systemPrompt: _prompt.text.trim(),
        workflow: scope.controller.settings.isAdvancedMode
            ? _workflow.text
                  .split('\n')
                  .map((step) => step.trim())
                  .where((step) => step.isNotEmpty)
                  .toList()
            : null,
      );
      if (!mounted) return;
      navigator.pop(saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final zh = scope.strings.isZh;
    final advanced = scope.controller.settings.isAdvancedMode;
    final palette = scope.palette;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.persona == null
                ? (zh ? '新建人格' : 'New persona')
                : (zh ? '编辑人格' : 'Edit persona'),
          ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isBuiltInCopy) ...[
                          Text(
                            zh ? '将此内置人格保存为自定义副本。' : 'Save this built-in persona as a custom copy.',
                            key: const Key('persona-built-in-note'),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.65,
                              color: palette.lineInk2,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          key: const Key('persona-name'),
                          controller: _name,
                          enabled: !_saving,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: zh ? '名称' : 'Name',
                            counterText: '',
                            errorStyle: TextStyle(color: palette.lineInk),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? (zh ? '请输入人格名称' : 'Enter a persona name')
                              : null,
                          onFieldSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('persona-prompt'),
                          controller: _prompt,
                          enabled: !_saving,
                          minLines: 5,
                          maxLines: 10,
                          decoration: InputDecoration(
                            labelText: zh ? '系统提示词' : 'System prompt',
                            alignLabelWithHint: true,
                            helperText: zh ? '可选。描述人格的语气、角色与回答方式；留空则只使用名称。' : 'Optional. Describe the persona’s voice, role and replies; leave blank to send no extra prompt.',
                            errorStyle: TextStyle(color: palette.lineInk),
                          ),
                        ),
                        if (advanced) ...[
                          const SizedBox(height: 24),
                          Divider(height: 1, color: palette.lineRule),
                          const SizedBox(height: 18),
                          Text(
                            zh ? '一行一步，两种模式都会把步骤作为提示词发给模型。' : 'Enter one step per line. Both modes send the steps to the model as part of the prompt.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.65,
                              color: palette.lineInk2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('persona-workflow'),
                            controller: _workflow,
                            enabled: !_saving,
                            minLines: 5,
                            maxLines: 10,
                            decoration: InputDecoration(
                              labelText: 'Workflow',
                              alignLabelWithHint: true,
                              hintText: zh
                                  ? '第一步\n第二步'
                                  : 'First step\nSecond step',
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (_saveError)
                          Semantics(
                            liveRegion: true,
                            child: Text(scope.strings.settingsSaveFailed),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: Text(scope.strings.cancel),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              key: const Key('persona-save'),
                              onPressed: _saving ? null : _save,
                              child: Text(
                                _saving
                                    ? scope.strings.saving
                                    : scope.strings.save,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
