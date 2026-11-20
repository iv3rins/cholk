import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_member.dart';
import '../../models/chat_models.dart';
import '../../models/chat_participant.dart';
import '../../theme/app_theme.dart';
import '../common.dart';
import '../participants/avatar_thumbnail.dart';
import '../participants/participant_avatar.dart';
import '../persona/persona_page.dart';
import '../selection_feedback.dart';

/// Recipient control for the composer. The label and the sheet describe the
/// same room: the default assistant, the global assistant profiles, then the
/// room-only members kept locally for the active conversation.
class RecipientPicker extends StatelessWidget {
  const RecipientPicker({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final strings = scope.strings;
    final ids = controller.selectedParticipantIds.toSet();
    final selected = controller.participants
        .where((participant) => ids.contains(participant.id))
        .toList(growable: false);
    final memberIds = controller.selectedChatMemberIds.toSet();
    final selectedMembers = controller.chatMembers
        .where((member) => memberIds.contains(member.id))
        .toList(growable: false);
    final count = selected.length + selectedMembers.length;
    // A room-only member may carry a persona prompt instead of a name.
    String memberLabel(ChatMember member) => member.name.trim().isNotEmpty
        ? member.name
        : (strings.isZh ? '未命名成员' : 'Unnamed member');
    final label = count == 0
        ? _assistantLabel(scope)
        : count == 1
        ? (selected.isNotEmpty
              ? selected.first.name
              : memberLabel(selectedMembers.first))
        : strings.recipientCount(count);

    return OutlinedButton(
      key: const ValueKey('chat-recipients'),
      onPressed: enabled ? () => _showRecipients(context) : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count == 1 && selected.isNotEmpty)
            ParticipantAvatar(
              name: selected.first.name,
              avatarBase64: selected.first.avatarBase64,
              size: 22,
            )
          else if (count == 1)
            ParticipantAvatar(
              name: memberLabel(selectedMembers.first),
              avatarBase64: selectedMembers.first.avatarBase64,
              size: 22,
            )
          else
            Icon(
              count == 0 ? Icons.person_outline : Icons.group_outlined,
              size: 19,
            ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }

  String _assistantLabel(AppScope scope) {
    final model = scope.controller.selectedChatModel?.model.trim() ?? '';
    if (model.isEmpty) return scope.strings.defaultAssistant;
    return CenteredNotice.label(
      dimension: scope.strings.defaultAssistant,
      value: model,
      zh: scope.strings.isZh,
    );
  }

  Future<void> _showRecipients(BuildContext context) async {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final strings = scope.strings;
    final draftKey = controller.draftKey;
    final result = await showModalBottomSheet<_RecipientChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      constraints: const BoxConstraints(maxWidth: 560),
      // A modal sheet is built above this scope, so it gets its own copy.
      builder: (_) => AppScope(
        controller: scope.controller,
        strings: scope.strings,
        palette: scope.palette,
        child: _RecipientSheet(
          participants: controller.participants,
          selectedIds: controller.selectedParticipantIds,
          members: controller.chatMembers,
          selectedMemberIds: controller.selectedChatMemberIds,
          models: controller.availableChatModels,
          isAdvanced: controller.settings.isAdvancedMode,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.manage) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const PersonaPage()));
      return;
    }
    // The sheet waited for Done; a different draft or mode means the answer
    // belongs to another conversation.
    if (draftKey != controller.draftKey) return;
    try {
      await controller.setSelectedParticipantIds(result.ids);
      await controller.setRoomMembers(result.members, result.memberIds);
    } catch (_) {
      if (context.mounted) showToast(context, strings.settingsSaveFailed);
    }
  }
}

class _RecipientChoice {
  const _RecipientChoice({
    required this.ids,
    this.members = const [],
    this.memberIds = const [],
    this.manage = false,
  });

  final List<String> ids;
  final List<ChatMember> members;
  final List<String> memberIds;
  final bool manage;
}

/// One row of the room: the default assistant, a global profile or a
/// room-only member.
class _RoomEntry {
  const _RoomEntry.assistant() : participant = null, member = null;
  const _RoomEntry.participant(ChatParticipant this.participant)
    : member = null;
  const _RoomEntry.member(ChatMember this.member) : participant = null;

  final ChatParticipant? participant;
  final ChatMember? member;

  bool get isAssistant => participant == null && member == null;
  String get id => participant?.id ?? member?.id ?? 'default-assistant';
  String get name => participant?.name ?? member?.name ?? '';
  String get model =>
      member?.model.model ?? participant?.configuration.model ?? '';
}

/// The form for one room-only member. Adding and editing share it, so the
/// member's name, avatar, persona prompt and model are edited in one place.
class _MemberDraft {
  _MemberDraft({
    String? id,
    String name = '',
    this.avatarBase64,
    String prompt = '',
    this.model,
  }) : id = id ?? newId(),
       idKnown = id != null,
       _name = TextEditingController(text: name),
       _prompt = TextEditingController(text: prompt);

  factory _MemberDraft.of(ChatMember member) => _MemberDraft(
    id: member.id,
    name: member.name,
    avatarBase64: member.avatarBase64,
    prompt: member.systemPrompt,
    model: member.model,
  );

  String id;

  /// True once the member has a saved identity; the same model may then be
  /// chosen again for another member that has its own id.
  final bool idKnown;
  String? avatarBase64;
  ChatModelRef? model;
  bool picking = false;
  bool avatarError = false;
  final TextEditingController _name;
  final TextEditingController _prompt;

  String get name => _name.text;
  String get prompt => _prompt.text;
  bool get canSave => _name.text.trim().isNotEmpty && model != null;

  /// Room members have no visible name of their own; the avatar starts from
  /// the persona prompt so the tile still reads as one identity.
  String get displayName {
    final name = _name.text.trim();
    if (name.isNotEmpty) return name;
    return _prompt.text.trim().characters.take(2).toString();
  }

  /// An unchanged avatar is written back byte for byte: re-encoding it on
  /// every edit would degrade the stored image.
  ChatMember? toMember(ChatMember? existing) {
    final model = this.model;
    if (model == null) return null;
    return ChatMember(
      id,
      _name.text.trim(),
      model,
      systemPrompt: _prompt.text.trim(),
      avatarBase64: avatarBase64 == existing?.avatarBase64
          ? existing?.avatarBase64
          : avatarBase64,
    );
  }

  void dispose() {
    _name.dispose();
    _prompt.dispose();
  }
}

class _RecipientSheet extends StatefulWidget {
  const _RecipientSheet({
    required this.participants,
    required this.selectedIds,
    required this.members,
    required this.selectedMemberIds,
    required this.models,
    required this.isAdvanced,
  });

  final List<ChatParticipant> participants;
  final List<String> selectedIds;
  final List<ChatMember> members;
  final List<String> selectedMemberIds;
  final List<ChatModelRef> models;
  final bool isAdvanced;

  @override
  State<_RecipientSheet> createState() => _RecipientSheetState();
}

class _RecipientSheetState extends State<_RecipientSheet> {
  late final Set<String> _selected = widget.selectedIds.toSet();
  late final Set<String> _memberIds = widget.selectedMemberIds.toSet();
  late List<ChatMember> _members = List.of(widget.members);
  late final List<ChatModelRef> _models = _modelChoices(widget.models);
  _MemberDraft? _draft;

  /// Two available references may share a model name, so deduplicate by
  /// reference rather than name.
  static List<ChatModelRef> _modelChoices(List<ChatModelRef> models) {
    final seen = <String>{};
    return [
      for (final model in models)
        if (model.model.trim().isNotEmpty && seen.add(_identity(model))) model,
    ];
  }

  static String _identity(ChatModelRef model) => [
    model.model.trim(),
    model.serverAddress ?? '',
    model.profileId ?? '',
    model.manualSource ?? '',
  ].join('\u0000');

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  bool get _assistantSelected => _selected.isEmpty && _memberIds.isEmpty;

  /// A saved member always has a name, so the tile never needs a placeholder
  /// for one; this only guards data from another source.
  String _memberLabel(ChatMember member) => member.name.trim().isNotEmpty
      ? member.name
      : (AppScope.of(context).strings.isZh ? '未命名成员' : 'Unnamed member');

  void _startAdding() {
    final previous = _draft;
    setState(() {
      _draft = _MemberDraft(model: _models.firstOrNull);
    });
    previous?.dispose();
  }

  void _startEditing(ChatMember member) {
    final previous = _draft;
    final draft = _MemberDraft.of(member);
    // A member whose model was not offered by name still shows its own
    // reference, so editing the other fields never silently swaps models.
    if (!_models.contains(draft.model)) _models.insert(0, draft.model!);
    setState(() => _draft = draft);
    previous?.dispose();
  }

  void _cancelDraft() {
    final previous = _draft;
    setState(() => _draft = null);
    previous?.dispose();
  }

  void _saveDraft() {
    final draft = _draft;
    if (draft == null || !draft.canSave) return;
    final existing = _members
        .where((member) => member.id == draft.id)
        .firstOrNull;
    final member = draft.toMember(existing);
    if (member == null) return;
    setState(() {
      final index = _members.indexWhere((entry) => entry.id == member.id);
      final next = [..._members];
      if (index < 0) {
        next.add(member);
      } else {
        next[index] = member;
      }
      _members = next;
      // An edited member stays selected; a new one joins the room at once.
      _memberIds.add(member.id);
      _draft = null;
    });
    draft.dispose();
  }

  Future<void> _pickAvatar(_MemberDraft draft) async {
    if (draft.picking) return;
    setState(() {
      draft.picking = true;
      draft.avatarError = false;
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
      if (mounted && identical(_draft, draft)) {
        setState(() => draft.avatarBase64 = avatar);
      }
    } catch (_) {
      if (mounted) setState(() => draft.avatarError = true);
    } finally {
      if (mounted) setState(() => draft.picking = false);
    }
  }

  void _removeMember(ChatMember member) {
    final previous = _draft;
    setState(() {
      _members = _members.where((entry) => entry.id != member.id).toList();
      _memberIds.remove(member.id);
      // Removing the member being edited closes its form.
      if (_draft?.id == member.id) _draft = null;
    });
    previous?.dispose();
  }

  void _toggle(_RoomEntry entry, bool? value) => setState(() {
    final member = entry.member;
    final participant = entry.participant;
    if (member != null) {
      value == true ? _memberIds.add(member.id) : _memberIds.remove(member.id);
    } else if (participant != null) {
      value == true
          ? _selected.add(participant.id)
          : _selected.remove(participant.id);
    } else {
      // The default assistant is the empty selection.
      _selected.clear();
      _memberIds.clear();
    }
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    final maxHeight = MediaQuery.sizeOf(context).height * .72;
    final draft = _draft;
    final editing = draft != null && draft.idKnown;
    final entries = <_RoomEntry>[
      const _RoomEntry.assistant(),
      for (final participant in widget.participants)
        _RoomEntry.participant(participant),
      for (final member in _members) _RoomEntry.member(member),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.replyParticipants,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.sharedChatHistory,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            // One scroll view holds the room list and the member form, so a
            // short window scrolls to any field instead of overflowing.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in entries) _tile(context, entry),
                  // The form sits after the list, above the footer buttons.
                  if (draft != null)
                    _memberForm(context, draft, editing: editing),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  _SheetAction(
                    key: const Key('recipient-add-member'),
                    onPressed: draft != null ? _cancelDraft : _startAdding,
                    icon: Icons.person_add_alt_1_outlined,
                    label: draft != null
                        ? (strings.isZh ? '取消' : 'Cancel')
                        : (strings.isZh ? '添加成员' : 'Add member'),
                  ),
                  if (widget.isAdvanced)
                    _SheetAction(
                      key: const Key('recipient-manage'),
                      onPressed: () => Navigator.pop(
                        context,
                        const _RecipientChoice(ids: [], manage: true),
                      ),
                      icon: Icons.manage_accounts_outlined,
                      // Shares the composer's wording: one phrase for the
                      // models-and-personas page in every place it appears.
                      label: strings.manageParticipants,
                    ),
                  FilledButton(
                    key: const Key('recipient-done'),
                    onPressed: () => Navigator.pop(
                      context,
                      _RecipientChoice(
                        ids: _selected.toList(),
                        members: _members,
                        memberIds: _memberIds.toList(),
                      ),
                    ),
                    child: Text(strings.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _RoomEntry entry) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final member = entry.member;
    final participant = entry.participant;
    final selected = entry.isAssistant
        ? _assistantSelected
        : member != null
        ? _memberIds.contains(member.id)
        : _selected.contains(participant!.id);
    final name = entry.isAssistant
        ? strings.defaultAssistant
        : member != null
        ? _memberLabel(member)
        : entry.name;
    final tile = CheckboxListTile(
      key: ValueKey('recipient-${entry.id}'),
      selected: selected,
      selectedTileColor: palette.active,
      secondary: participant != null
          ? ParticipantAvatar(
              name: participant.name,
              avatarBase64: participant.avatarBase64,
              size: 32,
            )
          : member != null
          ? ParticipantAvatar(
              name: _memberLabel(member),
              avatarBase64: member.avatarBase64,
              size: 32,
            )
          : const Icon(Icons.person_outline),
      title: Row(
        children: [
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (member != null) ...[
            const SizedBox(width: 6),
            Text(
              strings.isZh ? '本会话' : 'This chat',
              style: TextStyle(fontSize: 11, color: palette.textTertiary),
            ),
          ],
        ],
      ),
      subtitle: entry.model.trim().isEmpty ? null : Text(entry.model),
      value: selected,
      // Selected rows invert to ink so the active set reads at a glance.
      activeColor: palette.textPrimary,
      checkColor: palette.background,
      onChanged: (value) => _toggle(entry, value),
    );
    if (member == null) return tile;
    return Row(
      children: [
        Expanded(child: tile),
        IconButton(
          key: ValueKey('recipient-edit-${member.id}'),
          tooltip: strings.isZh ? '编辑此成员' : 'Edit member',
          icon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: () => _startEditing(member),
        ),
        IconButton(
          key: ValueKey('recipient-remove-${member.id}'),
          tooltip: strings.isZh ? '移除此成员' : 'Remove member',
          icon: const Icon(Icons.close_rounded, size: 16),
          onPressed: () => _removeMember(member),
        ),
      ],
    );
  }

  /// One form for adding and for editing: the nickname and the persona prompt
  /// are edited here, and the avatar is kept locally as a thumbnail, never as
  /// an external URL.
  Widget _memberForm(
    BuildContext context,
    _MemberDraft draft, {
    required bool editing,
  }) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final zh = scope.strings.isZh;
    // The form shares the sheet with the room list, so it is part of the same
    // scroll view: a short window can still reach the confirm button.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Two rows keep the form inside a short window: the avatar previews
          // the stored thumbnail, and nothing here adds a second field.
          Row(
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: draft._name,
                builder: (_, _, _) => ParticipantAvatar(
                  name: draft.displayName,
                  avatarBase64: draft.avatarBase64,
                  size: 32,
                ),
              ),
              Expanded(
                child: TextField(
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                  key: const Key('recipient-member-name'),
                  controller: draft._name,
                  autofocus: !editing,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    hintText: zh ? '昵称' : 'Name',
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                key: const Key('recipient-member-avatar'),
                tooltip: zh ? '选择头像' : 'Choose avatar',
                icon: const Icon(Icons.image_outlined, size: 18),
                onPressed: draft.picking ? null : () => _pickAvatar(draft),
              ),
              IconButton(
                key: const Key('recipient-member-avatar-clear'),
                tooltip: zh ? '移除头像' : 'Remove avatar',
                icon: const Icon(Icons.hide_image_outlined, size: 18),
                onPressed: draft.picking || draft.avatarBase64 == null
                    ? null
                    : () => setState(() => draft.avatarBase64 = null),
              ),
            ],
          ),
          if (draft.avatarError)
            Semantics(
              liveRegion: true,
              child: Text(
                zh
                    ? '无法读取头像。请选择不超过 8 MB 的图片。'
                    : 'Could not read this avatar. Choose an image up to 8 MB.',
                style: TextStyle(fontSize: 12, color: palette.lineInk),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                  key: const Key('recipient-member-prompt'),
                  controller: draft._prompt,
                  minLines: 1,
                  maxLines: 1,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: zh ? '人格提示词' : 'Persona prompt',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('recipient-member-confirm'),
                onPressed: draft.canSave ? _saveDraft : null,
                child: Text(
                  editing ? (zh ? '保存' : 'Save') : (zh ? '加入' : 'Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_models.isEmpty)
                Text(
                  zh
                      ? '暂无可用模型。请先登录或配置 API。'
                      : 'No models available. Sign in or configure an API.',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                )
              else
                for (final model in _models)
                  ChoiceChip(
                    // The same model name may be offered twice under different
                    // references, so identity comes from the position.
                    key: ValueKey('recipient-model-${_models.indexOf(model)}'),
                    label: Text(model.model),
                    selected: draft.model == model,
                    showCheckmark: false,
                    selectedColor: palette.textPrimary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: draft.model == model
                          ? palette.background
                          : palette.textPrimary,
                    ),
                    // The default assistant is the empty selection, so a
                    // member always keeps a model of its own.
                    onSelected: (_) => setState(() => draft.model = model),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A plain action for the sheet footer: no Material text colour, so the label
/// phrase appears exactly once next to the button.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: palette.textPrimary),
      label: Text(label, style: TextStyle(color: palette.textPrimary)),
    );
  }
}
