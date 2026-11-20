import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../models/chat_participant.dart';
import '../../models/model_configuration.dart';
import '../../theme/app_theme.dart';
import '../settings/model_configuration_fields.dart';
import '../settings/settings_frame.dart';
import 'avatar_thumbnail.dart';
import 'participant_avatar.dart';

Future<void> openParticipantEditor(
  BuildContext context, {
  ChatParticipant? participant,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => ParticipantEditorPage(participant: participant),
  ),
);

class ParticipantEditorPage extends StatefulWidget {
  const ParticipantEditorPage({super.key, this.participant});

  final ChatParticipant? participant;

  @override
  State<ParticipantEditorPage> createState() => _ParticipantEditorPageState();
}

class _ParticipantEditorPageState extends State<ParticipantEditorPage> {
  final _identityKey = GlobalKey<FormState>();
  final _fieldsKey = GlobalKey<ModelConfigurationFieldsState>();
  final _scrollController = ScrollController();
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final String _id;
  String? _avatar;
  String? _personaId;
  bool _picking = false;
  bool _saving = false;
  bool _verifying = false;
  bool _avatarError = false;
  bool _saveError = false;

  @override
  void initState() {
    super.initState();
    final participant = widget.participant;
    _id = participant?.id ?? newId();
    _name = TextEditingController(text: participant?.name ?? '');
    _prompt = TextEditingController(text: participant?.systemPrompt ?? '');
    _avatar = participant?.avatarBase64;
    _personaId = participant?.personaId;
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _avatarError = false;
    });
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (!mounted || files.isEmpty) return;
      final file = files.first;
      if ((await file.length() ?? 0) > maxAvatarFileBytes) {
        throw const FormatException('Avatar file too large');
      }
      if (!mounted) return;
      final bytes = await file.readAsBytes();
      final avatar = await encodeAvatarThumbnail(bytes);
      if (mounted) setState(() => _avatar = avatar);
    } catch (_) {
      if (mounted) setState(() => _avatarError = true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || _verifying) return;
    final fields = _fieldsKey.currentState!;
    final hasName = _identityKey.currentState!.validate();
    final hasConnection = fields.validate();
    if (!hasName || !hasConnection) {
      if (!hasName) {
        _scrollController.jumpTo(0);
      } else {
        await Scrollable.ensureVisible(fields.context, alignment: 0);
      }
      return;
    }
    final controller = AppScope.of(context).controller;
    setState(() {
      _saving = true;
      _saveError = false;
    });
    try {
      await controller.saveParticipant(
        ChatParticipant(
          id: _id,
          name: _name.text.trim(),
          configuration: fields.draft,
          systemPrompt: _prompt.text.trim(),
          personaId: _personaId,
          avatarBase64: _avatar,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final zh = strings.isZh;
    final palette = scope.palette;
    final editing = widget.participant != null;
    final title = editing
        ? (zh ? '编辑参与模型' : 'Edit model')
        : (zh ? '添加参与模型' : 'Add model');
    // While the keyboard is up, the fixed action bar would sit on top of it
    // and squeeze the form; hide it so the focused field keeps the space.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    const scrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 96);
    final content = SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Form(
                    key: _identityKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SettingsSectionTitle(zh ? '显示信息' : 'Identity'),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _name,
                              builder: (_, value, _) => ParticipantAvatar(
                                name: value.text,
                                avatarBase64: _avatar,
                                size: 56,
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _picking || _saving
                                  ? null
                                  : _pickAvatar,
                              child: Text(
                                _picking
                                    ? (zh ? '正在读取…' : 'Reading…')
                                    : (zh ? '选择头像' : 'Choose avatar'),
                              ),
                            ),
                            if (_avatar != null)
                              TextButton(
                                onPressed: _picking || _saving
                                    ? null
                                    : () => setState(() {
                                        _avatar = null;
                                        _avatarError = false;
                                      }),
                                child: Text(zh ? '移除头像' : 'Remove avatar'),
                              ),
                          ],
                        ),
                        if (_avatarError) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              zh ? '无法读取头像。请选择不超过 8 MB 的图片。' : 'Could not read this avatar. Choose an image up to 8 MB.',
                              style: TextStyle(color: palette.lineInk),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('participant-name'),
                          controller: _name,
                          enabled: !_saving,
                          maxLength: 80,
                          scrollPadding: scrollPadding,
                          decoration: InputDecoration(
                            labelText: zh ? '显示名称' : 'Display name',
                            counterText: '',
                            errorStyle: TextStyle(color: palette.lineInk),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? (zh ? '请输入显示名称' : 'Enter a display name')
                              : null,
                        ),
                        if (scope.controller.settings.isAdvancedMode) ...[
                          const SizedBox(height: 18),
                          DropdownButtonFormField<String?>(
                            key: const Key('participant-persona'),
                            initialValue: _personaId,
                            decoration: InputDecoration(
                              labelText: zh ? '人格' : 'Persona',
                              helperText: zh ? '人格与下方角色提示词会一并使用。' : 'The persona and role prompt below are used together.',
                              helperMaxLines: 2,
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                child: Text(zh ? '不使用人格' : 'No persona'),
                              ),
                              for (final persona
                                  in scope.controller.personaOptions)
                                DropdownMenuItem<String?>(
                                  value: persona.id,
                                  child: Text(
                                    persona.name(zh),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (id) => setState(() => _personaId = id),
                          ),
                        ],
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('participant-prompt'),
                          controller: _prompt,
                          enabled: !_saving,
                          minLines: 3,
                          maxLines: typing ? 4 : 6,
                          scrollPadding: scrollPadding,
                          decoration: InputDecoration(
                            labelText: zh
                                ? '系统提示词（可选）'
                                : 'System prompt (optional)',
                            alignLabelWithHint: true,
                            helperText: zh
                                ? '留空时使用通用助手。'
                                : 'Leave blank for a general assistant.',
                            helperMaxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Divider(color: palette.lineRule),
                  const SizedBox(height: 14),
                  SettingsSectionTitle(strings.apiConnection),
                  ModelConfigurationFields(
                    key: _fieldsKey,
                    initialConfiguration:
                        widget.participant?.configuration ??
                        const ModelConfiguration(),
                    enabled: !_saving,
                    onVerifyingChanged: (value) =>
                        setState(() => _verifying = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final actions = SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.lineRule)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (_saveError)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.settingsSaveFailed),
                ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                key: const Key('participant-save'),
                onPressed: _saving || _picking || _verifying ? null : _save,
                child: Text(_saving ? strings.saving : strings.save),
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          children: [
            Expanded(child: content),
            if (!typing) actions,
          ],
        ),
      ),
    );
  }
}
