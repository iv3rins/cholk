import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../chat/agent_mentions.dart';
import '../../chat/attachments.dart';
import '../../models/chat_member.dart';
import '../../models/chat_models.dart';
import '../../models/chat_preferences.dart';
import '../../models/model_configuration.dart';
import '../../models/persona.dart';
import '../../state/chat_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import '../participants/participant_avatar.dart';
import '../persona/persona_editor_page.dart';
import '../settings/settings_dialog.dart';
import '../selection_feedback.dart';
import 'local_image.dart';
import 'recipient_picker.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _focus = FocusNode();
  late final ChatController _chat;
  late final String _draftKey;
  late final TextEditingController _text;
  TextEditingValue? _previousValue;
  bool _initialized = false;
  bool _picking = false;
  bool _dismissed = false;
  int _suggestion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _chat = AppScope.of(context).controller;
    _draftKey = _chat.draftKey;
    _text = TextEditingController(text: _chat.draftText);
    _previousValue = _text.value;
    _text.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _text.value;
    if (_chat.draftKey == _draftKey && value.text != _previousValue?.text) {
      _chat.setDraftText(value.text);
    }
    _previousValue = value;
    setState(() {
      _dismissed = false;
      _suggestion = 0;
    });
  }

  void _onFocusChanged() => setState(() => _dismissed = false);

  bool get _canSend =>
      _text.text.trim().isNotEmpty || _chat.draftFiles.isNotEmpty;

  Future<void> _send() async {
    if (_chat.activeStreaming) {
      _chat.stopReply();
      return;
    }
    if (_picking || !_canSend) return;
    final text = _text.text;
    if (!_chat.hasConnectionFor(text)) {
      await showSettingsDialog(context);
      return;
    }
    final files = List<FileAttachment>.of(_chat.draftFiles);
    final error = _chat.draftAttachmentError(files, text: text);
    if (error != null) {
      showToast(context, error);
      return;
    }
    final sent = await _chat.sendMessage(text, files);
    if (sent && mounted && _chat.draftKey == _draftKey && _text.text == text) {
      _text.clear();
    }
  }

  Future<void> _pickFiles() async {
    if (_picking) return;
    final allowed = _chat
        .configurationsFor(_text.text)
        .map(acceptedExtensionsFor)
        .reduce((shared, extensions) => shared.intersection(extensions));
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed.toList(),
      );
      if (result.isEmpty || !mounted || _chat.draftKey != _draftKey) return;
      final picked = <PickedFileInfo>[];
      for (final file in result) {
        final path = file.path;
        picked.add(
          PickedFileInfo(
            path: path,
            name: file.name,
            size: await file.length() ?? 0,
            bytes: path == null ? await file.readAsBytes() : null,
          ),
        );
      }
      if (!mounted || _chat.draftKey != _draftKey) return;
      final error = await _chat.addDraftFiles(picked);
      if (error != null && mounted) showToast(context, error);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  MentionQuery? get _mentionQuery {
    final value = _text.value;
    if (!_focus.hasFocus ||
        _dismissed ||
        _chat.activeStreaming ||
        !value.selection.isCollapsed ||
        value.isComposingRangeValid) {
      return null;
    }
    final query = AgentMentions.queryAt(value.text, value.selection.baseOffset);
    return query == null || query.query.endsWith(' ') ? null : query;
  }

  void _replace(int start, int end, String insertion) {
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _focus.requestFocus();
  }

  void _openMentions() {
    if (_mentionQuery != null) {
      setState(() => _dismissed = false);
      return;
    }
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    _replace(
      start,
      end,
      AgentMentions.canStartAt(_text.text, start) ? '@' : ' @',
    );
  }

  void _chooseMention(MentionQuery query, MentionOption option) {
    // If the caret is inside the same existing handle, consume its suffix too.
    final before = _text.text.substring(query.start, query.end).toLowerCase();
    final handle = option.handle.toLowerCase();
    var end = query.end;
    if (handle.startsWith(before)) {
      final suffix = handle.substring(before.length);
      if (_text.text.toLowerCase().startsWith(suffix, end)) {
        end += suffix.length;
      }
    }
    final space = end < _text.text.length && _text.text[end] == ' ' ? '' : ' ';
    _replace(query.start, end, '${option.handle}$space');
  }

  KeyEventResult _keyEvent(
    KeyEvent event,
    MentionQuery? query,
    List<MentionOption> options,
  ) {
    if (event is! KeyDownEvent || _text.value.isComposingRangeValid) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (query != null && key == LogicalKeyboardKey.escape) {
      setState(() => _dismissed = true);
      return KeyEventResult.handled;
    }
    if (options.isNotEmpty &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final direction = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _suggestion = (_suggestion + direction) % options.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (query != null && options.isNotEmpty) {
        _chooseMention(
          query,
          options[_suggestion.clamp(0, options.length - 1)],
        );
      } else {
        _send();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final streaming = _chat.activeStreaming;
    final files = _chat.draftFiles;
    final work = _chat.chatMode == ChatMode.work;
    final disabled =
        streaming ||
        _picking ||
        (_chat.activeId != null && _chat.activeSession == null);
    final usesDeepSeek = _chat
        .configurationsFor(_text.text)
        .any((configuration) => configuration.protocol == ApiProtocol.deepseek);
    final mentions = AgentMentions(_chat.mentionParticipants);
    final query = mentions.options.isEmpty ? null : _mentionQuery;
    final options = query == null
        ? const <MentionOption>[]
        : mentions.options
              .where(
                (option) =>
                    option.participant.name.toLowerCase().contains(
                      query.query,
                    ) ||
                    option.handle
                        .substring(1)
                        .toLowerCase()
                        .startsWith(query.query),
              )
              .toList();
    final mentioned = mentions.resolve(_text.text);

    final still = MediaQuery.disableAnimationsOf(context);
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(right: 5, bottom: 5),
      decoration: BoxDecoration(
        // A hard second-drum offset: no blur, the sheet sits on its ink.
        boxShadow: [
          BoxShadow(
            color: focused ? palette.signal : palette.accent,
            offset: focused ? const Offset(5, 5) : Lineism.misprint,
          ),
        ],
      ),
      child: Material(
        color: palette.background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.lineInk, width: Lineism.base),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                children: [
                  Flexible(child: RecipientPicker(enabled: !disabled)),
                  const SizedBox(width: 4),
                  Flexible(child: _AssistantMenu(enabled: !disabled)),
                ],
              ),
            ),
            Divider(height: Lineism.hair, color: palette.lineRule),
            if (mentioned.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(
                  '${strings.replyTo} · ${mentioned.map((agent) => agent.name).join(' / ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => _DraftAttachment(
                      file: files[index],
                      onRemove: () => _chat.removeDraftFile(files[index].id),
                    ),
                  ),
                ),
              ),
            if (query != null)
              _MentionSuggestions(
                options: options,
                selected: _suggestion,
                onSelect: (option) => _chooseMention(query, option),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Focus(
                onKeyEvent: (_, event) => _keyEvent(event, query, options),
                child: TextField(
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                  key: const Key('message-draft'),
                  controller: _text,
                  focusNode: _focus,
                  minLines: work ? 2 : 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: Lineism.serif.copyWith(
                    fontSize: 16,
                    height: 1.5,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: work
                        ? strings.workPlaceholder
                        : strings.inputPlaceholder,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: Lineism.serif.copyWith(
                      fontSize: 16,
                      color: palette.textCaption,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              child: Row(
                children: [
                  AppIconButton(
                    key: const Key('mention-agent'),
                    icon: Icons.alternate_email_rounded,
                    tooltip: mentions.options.isEmpty
                        ? strings.mentionNeedsGroup
                        : strings.mentionAgent,
                    size: 44,
                    onPressed: disabled || mentions.options.isEmpty
                        ? null
                        : _openMentions,
                  ),
                  AppIconButton(
                    icon: Icons.attach_file_rounded,
                    tooltip: strings.uploadFile,
                    size: 44,
                    onPressed: disabled ? null : _pickFiles,
                  ),
                  if (usesDeepSeek) _ConversationTools(enabled: !streaming),
                  const Spacer(),
                  FilledButton(
                    key: const Key('send-draft'),
                    onPressed: streaming || (!disabled && _canSend)
                        ? _send
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 44),
                      padding: EdgeInsets.zero,
                      backgroundColor: streaming ? palette.signal : null,
                    ),
                    child: Tooltip(
                      message: streaming ? strings.stop : strings.send,
                      child: Icon(
                        streaming
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Assistant menu: the default assistant's model, the conversation persona,
/// and - in advanced mode only - an entry point that edits the persona the
/// current conversation is using.
class _AssistantMenu extends StatelessWidget {
  const _AssistantMenu({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final controller = scope.controller;
    final zh = strings.isZh;
    final override = controller.chatPersonaOverride;
    final personaId = override ?? controller.settings.personaId;
    final persona = controller.personaForId(personaId);
    final models = controller.availableChatModels;
    final selected = controller.selectedChatModel;

    return PopupMenuButton<_AssistantAction>(
      key: const Key('chat-assistant'),
      tooltip: strings.defaultAssistant,
      enabled: enabled,
      position: PopupMenuPosition.over,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      onSelected: (action) => _apply(context, action, persona),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: _caption(
            context,
            zh
                ? '\u9ed8\u8ba4\u52a9\u624b\u6a21\u578b'
                : 'Default assistant model',
          ),
        ),
        for (final model in models)
          CheckedPopupMenuItem(
            key: ValueKey('chat-model-${model.model}'),
            value: _AssistantAction.model(model),
            checked: model == selected,
            child: Text(model.model),
          ),
        if (models.isEmpty)
          PopupMenuItem(
            enabled: false,
            child: Text(
              zh
                  ? '\u6682\u65e0\u53ef\u7528\u6a21\u578b'
                  : 'No model available',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: _caption(context, strings.chatPersona),
        ),
        CheckedPopupMenuItem(
          key: const ValueKey('chat-persona-defaults'),
          value: const _AssistantAction.persona(null),
          checked: override == null,
          child: Text(strings.followDefaults),
        ),
        for (final option in controller.personaOptions)
          CheckedPopupMenuItem(
            key: ValueKey('chat-persona-${option.id}'),
            value: _AssistantAction.persona(option.id),
            checked: option.id == override,
            child: Text(option.name(zh)),
          ),
        if (controller.settings.isAdvancedMode) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            key: const ValueKey('chat-persona-edit'),
            value: const _AssistantAction.edit(),
            child: Text(
              zh
                  ? '\u7f16\u8f91\u5f53\u524d\u4eba\u683c'
                  : 'Edit current persona',
            ),
          ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 17,
              color: enabled
                  ? scope.palette.lineInk
                  : scope.palette.textCaption,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selected?.model ?? strings.defaultAssistant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? scope.palette.lineInk
                      : scope.palette.textCaption,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _caption(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );

  Future<void> _apply(
    BuildContext context,
    _AssistantAction action,
    Persona persona,
  ) async {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final controller = scope.controller;
    final draftKey = controller.draftKey;
    final mode = controller.chatMode;
    try {
      switch (action.kind) {
        case _AssistantKind.model:
          await controller.setChatModel(action.model!);
          if (!context.mounted || draftKey != controller.draftKey) return;
          // Report the value that actually took effect, not the tap.
          final applied = controller.selectedChatModel ?? action.model!;
          showCenteredNotice(
            context,
            CenteredNotice.label(
              dimension: strings.defaultAssistant,
              value: applied.model,
              zh: strings.isZh,
            ),
          );
        case _AssistantKind.persona:
          await controller.setChatPersona(action.personaId);
        case _AssistantKind.edit:
          final saved = await openPersonaEditor(context, persona: persona);
          if (saved == null || !context.mounted) return;
          // Saving in another draft or mode must not retarget this chat.
          if (draftKey != controller.draftKey || mode != controller.chatMode) {
            return;
          }
          await controller.setChatPersona(saved.id);
          if (!context.mounted) return;
          showCenteredNotice(
            context,
            CenteredNotice.label(
              dimension: strings.chatPersona,
              value: saved.name(strings.isZh),
              zh: strings.isZh,
            ),
          );
      }
    } catch (_) {
      if (context.mounted) showToast(context, strings.settingsSaveFailed);
    }
  }
}

enum _AssistantKind { model, persona, edit }

class _AssistantAction {
  const _AssistantAction.model(this.model)
    : kind = _AssistantKind.model,
      personaId = null;
  const _AssistantAction.persona(this.personaId)
    : kind = _AssistantKind.persona,
      model = null;
  const _AssistantAction.edit()
    : kind = _AssistantKind.edit,
      model = null,
      personaId = null;

  final _AssistantKind kind;
  final ChatModelRef? model;
  final String? personaId;
}

class _ConversationTools extends StatelessWidget {
  const _ConversationTools({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final chat = scope.controller;
    final thinking = chat.settings.thinking;
    final search = chat.settings.search;
    return PopupMenuButton<bool>(
      tooltip: strings.moreTools,
      enabled: enabled,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.tune_outlined,
        size: 19,
        color: thinking || search
            ? scope.palette.lineInk
            : scope.palette.lineInk2,
      ),
      onSelected: (think) =>
          think ? chat.setThinking(!thinking) : chat.setSearch(!search),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: true,
          checked: thinking,
          child: Text(strings.thinkingSwitch),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: search,
          child: Text(strings.search),
        ),
      ],
    );
  }
}

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<MentionOption> options;
  final int selected;
  final ValueChanged<MentionOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Text(
          scope.strings.noMatchingAgents,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final highlighted = selected.clamp(0, options.length - 1);
    // Keep a keyboard-highlighted item visible without scrolling the composer.
    final first = (highlighted - 1).clamp(
      0,
      options.length > 3 ? options.length - 3 : 0,
    );
    return TextFieldTapRegion(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 124),
        child: ListView.builder(
          key: ValueKey(first),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          shrinkWrap: true,
          itemCount: options.length - first,
          itemBuilder: (context, index) {
            final option = options[first + index];
            return ListTile(
              key: ValueKey('mention-${option.participant.id}'),
              dense: true,
              minTileHeight: 42,
              selected: first + index == highlighted,
              selectedTileColor: scope.palette.hover,
              leading: ParticipantAvatar(
                name: option.participant.name,
                avatarBase64: option.participant.avatarBase64,
                size: 22,
              ),
              title: Text(
                '@${option.participant.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: first + index == highlighted
                  ? const Icon(Icons.keyboard_return_rounded, size: 16)
                  : null,
              onTap: () => onSelect(option),
            );
          },
        ),
      ),
    );
  }
}

class _DraftAttachment extends StatelessWidget {
  const _DraftAttachment({required this.file, required this.onRemove});

  final FileAttachment file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (file.isImage)
          LocalAttachmentImage(file: file, size: 64, radius: 0)
        else
          Container(
            width: 180,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: palette.lineRule, width: Lineism.hair),
              color: Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  file.mimeType.toLowerCase().startsWith('audio/')
                      ? Icons.audio_file_outlined
                      : Icons.description_outlined,
                  size: 22,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: palette.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: palette.background,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: palette.lineInk,
                    width: Lineism.hair,
                  ),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: palette.lineInk,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
