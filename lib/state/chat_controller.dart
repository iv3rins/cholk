import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import '../api/account_client.dart';
import '../api/api_client.dart';
import '../api/api_types.dart';
import '../api/chat_gateway.dart';
import '../chat/agent_mentions.dart';
import '../chat/attachments.dart';
import '../chat/chat_request.dart';
import '../chat/group_history.dart';
import '../chat/reply_merge.dart';
import '../models/app_settings.dart';
import '../models/chat_models.dart';
import '../models/chat_member.dart';
import '../models/chat_participant.dart';
import '../models/chat_preferences.dart';
import '../models/model_configuration.dart';
import '../models/persona.dart';
import '../storage/session_store.dart';
import '../storage/settings_store.dart' show SettingsStore;

class ChatRequestDebug {
  ChatRequestDebug._({
    required this.sessionId,
    required this.model,
    required this.protocol,
    required this.participantName,
    required this.personas,
    required this.systemPrompt,
  });

  final String sessionId;
  final String model;
  final ApiProtocol protocol;
  final String? participantName;
  final List<Persona> personas;
  final String systemPrompt;
  int get systemChars => systemPrompt.length;
  final int startedAt = nowMs();
  ReplyStatus _status = ReplyStatus.streaming;
  String? _errorKind;
  int? _httpStatus;
  String? _errorMessage;

  ReplyStatus get status => _status;
  String? get errorKind => _errorKind;
  int? get httpStatus => _httpStatus;
  String? get errorMessage => _errorMessage;
}

typedef _RequestSystem = ({String prompt, List<Persona> personas});

class PickedFileInfo {
  const PickedFileInfo({
    this.path,
    required this.name,
    required this.size,
    this.bytes,
  });

  final String? path;
  final String name;
  final int size;
  final Uint8List? bytes;
}

typedef _ModelTarget = ({
  ModelConfiguration configuration,
  ChatParticipant? participant,
  ChatModelRef reference,
});

class ChatController extends ChangeNotifier {
  ChatController({
    ApiClient? apiClient,
    SettingsStore? settingsStore,
    SessionStore? sessionStore,
    ChatGateway? chatGateway,
    AccountClient? accountClient,
    this.onReplyDelivered,
  }) : api = apiClient ?? ApiClient(),
       _settingsStore = settingsStore ?? SettingsStore(),
       _sessionStore = sessionStore ?? SessionStore(),
       account = accountClient ?? AccountClient() {
    _gateway =
        chatGateway ??
        ChatGateway(
          legacyClient: api,
          readAttachment: _sessionStore.readAttachment,
        );
    // Account state is memory-only, so a reply must stop using a token the
    // moment it disappears. A listenable rebuild keeps the composer honest.
    account.addListener(_notifyNow);
  }

  final ApiClient api;

  /// Server sign-in state. The token lives in this object's memory only.
  final AccountClient account;

  /// Called once when a stream successfully adds visible reply text.
  Future<void> Function()? onReplyDelivered;

  /// Called when the user's message is accepted, without waiting for a reply.
  Future<void> Function()? onMessageAccepted;

  final SettingsStore _settingsStore;
  final SessionStore _sessionStore;
  late final ChatGateway _gateway;

  AppSettings settings = AppSettings();
  bool ready = false;
  bool initError = false;
  String? activeId;

  List<SessionSummary> summaries = [];
  final Map<String, ChatSession> _cache = {};
  final Map<String, Future<ChatSession?>> _sessionLoads = {};
  final Map<String, List<CancelToken>> _streaming = {};
  final Map<String, Future<void>> _batchSaves = {};
  final Set<String> _titleRequests = {};
  final Set<String> _deletedSessions = {};

  final Map<String, String> _drafts = {};
  final Map<String, List<FileAttachment>> _draftFiles = {};
  static const _debugLimit = 40;
  final _requestDebug = <ChatRequestDebug>[];
  bool _debugRecording = false;
  bool get debugRecording => _debugRecording;
  List<ChatRequestDebug> get activeRequestDebug => [
    for (final record in _requestDebug.reversed)
      if (record.sessionId == activeId) record,
  ];

  void setDebugRecording(bool enabled) {
    if (_debugRecording == enabled) return;
    _debugRecording = enabled;
    if (!enabled) _requestDebug.clear();
    _notifyNow();
  }

  List<ChatParticipant> _participants = const [];
  List<Persona> _customPersonas = const [];
  List<String> _nextParticipantIds = const [];
  ChatMode _nextMode = ChatMode.chat;
  final _nextPersonas = <ChatMode, String?>{};
  ChatModelRef? _nextModel;
  List<ChatMember> _nextMembers = const [];
  List<String> _nextMemberIds = const [];

  Timer? _notifyTimer;
  Timer? _draftSaveTimer;
  bool _disposed = false;
  final _workspaceChanges = ValueNotifier<int>(0);

  /// Changes to navigation, settings, and request lifecycle. The controller
  /// itself also emits updates for in-progress message and attachment data.
  Listenable get workspaceChanges => _workspaceChanges;

  Future<void> init() async {
    try {
      settings = await _settingsStore.load();
      _participants = await _settingsStore.loadParticipants();
      _customPersonas = await _settingsStore.loadPersonas();
      api.origin = settings.apiOrigin;
      summaries = await _sessionStore.loadIndex();
      if (summaries.isEmpty) {
        summaries = await _sessionStore.scanSessions();
        if (summaries.isNotEmpty) {
          await _sessionStore.saveIndex(summaries);
        }
      }
      _sortSummaries();
      await _loadDrafts();
    } catch (error) {
      initError = true;
      debugPrint('Failed to initialize chat: $error');
    }
    ready = true;
    _notifyNow();
  }

  ChatSession? get activeSession =>
      activeId == null ? null : cachedSession(activeId!);

  ChatSession? cachedSession(String id) => _cache[id];

  /// Reads a conversation without selecting it or replacing its live cache.
  Future<ChatSession?> readSession(String id) async =>
      cachedSession(id) ?? await _sessionStore.loadSession(id);

  bool isStreaming(String? id) => id != null && _streaming.containsKey(id);

  bool get activeStreaming => isStreaming(activeId);

  /// True while a finished batch is still saving. Tests and monitoring use it
  /// to know when the conversation has genuinely come to rest.
  bool get hasRunningWork => _streaming.isNotEmpty || _batchSaves.isNotEmpty;

  List<ChatParticipant> get participants => List.unmodifiable(_participants);

  List<Persona> get personaOptions => [...personas, ..._customPersonas];

  Persona personaForId(String id) =>
      personaOptions.where((persona) => persona.id == id).firstOrNull ??
      personas.first;

  Future<Persona> savePersona({
    String? id,
    required String name,
    required String systemPrompt,
    List<String>? workflow,
  }) async {
    final previous = id == null ? null : personaForId(id);
    if (previous != null && !previous.isCustom) {
      throw const FormatException('Only custom personas can be edited');
    }
    final persona = Persona.custom(
      id: id ?? newId(),
      name: name,
      systemPrompt: systemPrompt,
      workflow:
          (settings.isAdvancedMode ? workflow : null) ??
          previous?.workflow ??
          const [],
    );
    return _storePersona(persona);
  }

  Future<Persona> importPersona(String json) =>
      _storePersona(Persona.importJson(json, id: newId()));

  Future<Persona> _storePersona(Persona persona) async {
    final next = [..._customPersonas];
    final index = next.indexWhere((entry) => entry.id == persona.id);
    if (index < 0) {
      next.add(persona);
    } else {
      next[index] = persona;
    }
    await _settingsStore.savePersonas(next);
    _customPersonas = next;
    _notifyNow();
    return persona;
  }

  List<String> get selectedParticipantIds {
    final ids = activeId == null
        ? _nextParticipantIds
        : activeSession?.selectedParticipantIds ?? const <String>[];
    return _knownParticipantIds(ids);
  }

  List<String> _knownParticipantIds(Iterable<String> ids) {
    final known = _participants.map((profile) => profile.id).toSet();
    return List.unmodifiable(ids.where(known.contains).toSet());
  }

  ChatMode get chatMode =>
      activeId == null ? _nextMode : activeSession?.mode ?? ChatMode.chat;

  String? get chatPersonaOverride =>
      activeId == null ? _nextPersonas[_nextMode] : activeSession?.personaId;

  List<ChatParticipant> get activeParticipants {
    final byId = {for (final profile in _participants) profile.id: profile};
    return [for (final id in selectedParticipantIds) byId[id]!];
  }

  /// The room for the active conversation: global profiles that are selected,
  /// then the room-only members that are selected. Each id appears once.
  List<ChatMember> get _roomEntries => [
    for (final profile in activeParticipants)
      ChatMember(
        profile.id,
        profile.name,
        _modelRefFor(profile.configuration, profile.id),
      ),
    for (final member in _membersInRoom)
      if (selectedChatMemberIds.contains(member.id) &&
          !selectedParticipantIds.contains(member.id))
        member,
  ];

  List<ChatMember> get _membersInRoom =>
      activeId == null ? _nextMembers : activeSession?.members ?? const [];

  List<ChatParticipant> get mentionParticipants => [
    ..._participants,
    for (final member in _membersInRoom) _targetForEntry(member).participant!,
  ];

  List<_ModelTarget> _targetsFor(String text) {
    if (text.contains('@')) {
      final mentioned = AgentMentions(mentionParticipants).resolve(text);
      if (mentioned.isNotEmpty) {
        final entries = {
          for (final profile in _participants)
            profile.id: ChatMember(
              profile.id,
              profile.name,
              _modelRefFor(profile.configuration, profile.id),
            ),
          for (final member in _membersInRoom) member.id: member,
        };
        return [
          for (final member in mentioned) _targetForEntry(entries[member.id]!),
        ];
      }
    }
    final room = _roomEntries;
    return room.isEmpty
        ? [_targetForModel(selectedChatModel ?? _manualRef())]
        : [for (final entry in room) _targetForEntry(entry)];
  }

  _ModelTarget _targetForEntry(ChatMember entry) {
    final profile = _participants
        .where((item) => item.id == entry.id)
        .firstOrNull;
    return _targetForModel(
      entry.model,
      identity: ChatParticipant(
        id: entry.id,
        name: entry.name,
        configuration: profile?.configuration ?? settings.modelConfiguration,
        // A room-only member owns its identity. Only a member backed by a global
        // profile reads that profile, and only for a field it left unset.
        systemPrompt: profile == null
            ? entry.systemPrompt
            : _ownOrProfile(entry.systemPrompt, profile.systemPrompt),
        personaId: entry.personaId ?? profile?.personaId,
        avatarBase64: entry.avatarBase64 ?? profile?.avatarBase64,
      ),
    );
  }

  /// Keeps the member's own text when it says anything, otherwise falls back to
  /// the global profile it is backed by.
  String _ownOrProfile(String own, String fallback) =>
      own.trim().isEmpty ? fallback : own;

  bool _hasConnection(List<_ModelTarget> targets) =>
      targets.every((target) => target.configuration.apiKey.trim().isNotEmpty);

  String get _serverAddress =>
      settings.serverAddress.trim().replaceAll(RegExp(r'/+$'), '');

  _ModelTarget _targetForModel(
    ChatModelRef reference, {
    ChatParticipant? identity,
  }) {
    final server = reference.serverAddress;
    final ModelConfiguration configuration;
    if (server != null) {
      final token =
          server == _serverAddress &&
              server == account.address &&
              account.models.contains(reference.model)
          ? account.token
          : null;
      configuration = ModelConfiguration(
        protocol: ApiProtocol.openaiCompatible,
        apiOrigin: '$server/v1',
        apiKey: token ?? '',
        model: reference.model,
      );
    } else {
      final profileId = reference.profileId;
      final source = profileId == null
          ? settings.modelConfiguration
          : _participants
                .where((item) => item.id == profileId)
                .firstOrNull
                ?.configuration;
      final matches =
          source != null && _modelRefFor(source, profileId) == reference;
      configuration = (source ?? const ModelConfiguration()).copyWith(
        model: reference.model,
        apiKey: matches ? source.apiKey : '',
      );
    }
    return (
      configuration: configuration,
      participant: identity,
      reference: reference,
    );
  }

  List<ChatModelRef> get availableChatModels => [
    if (_serverAddress.isNotEmpty &&
        _serverAddress == account.address &&
        account.token != null)
      for (final model in account.models)
        ChatModelRef(model, serverAddress: account.address),
    if (settings.modelConfiguration.apiKey.isNotEmpty || _serverAddress.isEmpty)
      _manualRef(),
    for (final profile in _participants)
      _modelRefFor(profile.configuration, profile.id),
  ];

  ChatModelRef _manualRef() => _modelRefFor(settings.modelConfiguration, null);

  ChatModelRef? get selectedChatModel {
    final stored = activeId == null ? _nextModel : activeSession?.model;
    if (stored != null) return stored;
    final models = availableChatModels;
    final preferred = settings.preferredChatModel;
    if (activeId == null && preferred != null && models.contains(preferred)) {
      return preferred;
    }
    return models.firstOrNull;
  }

  bool get hasChatConnection => hasConnectionFor('');

  bool hasConnectionFor(String text) => _hasConnection(_targetsFor(text));

  List<ModelConfiguration> configurationsFor(String text) => List.unmodifiable(
    _targetsFor(text).map((target) => target.configuration),
  );

  /// Members and the assistant model for the open conversation. A draft that
  /// has not been sent yet keeps them in controller state instead, so opening
  /// another session never leaks the draft's room into it.
  void _writeRoom(
    ChatSession? session, {
    List<String>? participantIds,
    ChatModelRef? model,
    List<String>? memberIds,
    List<ChatMember>? members,
  }) {
    if (session == null) {
      if (participantIds != null) _nextParticipantIds = participantIds;
      if (model != null) _nextModel = model;
      if (memberIds != null) _nextMemberIds = memberIds;
      if (members != null) _nextMembers = members;
      return;
    }
    if (participantIds != null) session.selectedParticipantIds = participantIds;
    if (model != null) session.model = model;
    if (memberIds != null) session.selectedMemberIds = memberIds;
    if (members != null) session.members = members;
  }

  Future<void> setChatMode(ChatMode mode) => _updateChatPreferences((session) {
    if (session == null) {
      _nextMode = mode;
    } else {
      session.mode = mode;
    }
  });

  Future<void> setChatPersona(String? id) => _updateChatPreferences((session) {
    final persona = id == null ? null : personaForId(id).id;
    if (session == null) {
      _nextPersonas[_nextMode] = persona;
    } else {
      session.personaId = persona;
    }
  });

  Future<void> _updateChatPreferences(
    void Function(ChatSession?) update,
  ) async {
    final id = activeId;
    if (id == null) {
      update(null);
      _notifyNow();
      return;
    }
    final session = activeSession ?? await _ensureSession(id);
    if (session == null || _deletedSessions.contains(id)) return;
    update(session);
    _notifyNow();
    if (!isStreaming(id)) await _sessionStore.saveSession(session);
  }

  Future<void> setSelectedParticipantIds(List<String> ids) async {
    final selection = _knownParticipantIds(ids);
    final id = activeId;
    if (id == null) {
      _writeRoom(null, participantIds: selection);
    } else {
      final session = activeSession ?? await _ensureSession(id);
      if (session == null || _deletedSessions.contains(id)) return;
      _writeRoom(session, participantIds: selection);
      // A running batch will save the updated session with all its replies.
      if (!isStreaming(id)) await _sessionStore.saveSession(session);
    }
    _notifyNow();
  }

  /// A profile's model reference. The transport marker is carried along so the
  /// reference resolves to that profile's own hand-filled connection, never to
  /// an account default.
  ChatModelRef _modelRefFor(
    ModelConfiguration configuration,
    String? profileId,
  ) => ChatModelRef(
    configuration.model,
    profileId: profileId,
    manualSource:
        '${configuration.protocol.name}:${configuration.normalizedOrigin}',
  );

  /// The default assistant's model for the active conversation, or null when
  /// the conversation follows the globally configured model.
  Future<void> setChatModel(ChatModelRef model) async {
    if (!availableChatModels.contains(model)) return;
    final value = model;
    final id = activeId;
    if (id == null) {
      _writeRoom(null, model: value);
    } else {
      final session = activeSession ?? await _ensureSession(id);
      if (session == null || _deletedSessions.contains(id)) return;
      _writeRoom(session, model: value);
      if (!isStreaming(id)) await _sessionStore.saveSession(session);
    }
    // The choice also seeds the next new conversation, and it is stored as a
    // credential-free reference.
    settings.preferredChatModel = value;
    try {
      await _settingsStore.setChatModel(value);
    } catch (error) {
      debugPrint('Failed to save the chat model preference: $error');
    }
    _notifyNow();
  }

  /// Members that exist only for the active conversation.
  List<ChatMember> get chatMembers => List.unmodifiable(_membersInRoom);

  List<String> get selectedChatMemberIds {
    final ids = activeId == null
        ? _nextMemberIds
        : activeSession?.selectedMemberIds ?? const <String>[];
    final known = _membersInRoom.map((member) => member.id).toSet();
    return List.unmodifiable(ids.where(known.contains));
  }

  /// Applies the room the sheet drafted. [members] is the accepted local list;
  /// [selectedIds] are the draft members kept for this turn. Ids that are not
  /// in [members] are dropped so a deleted member cannot linger.
  Future<void> setRoomMembers(
    List<ChatMember> members,
    List<String> selectedIds,
  ) async {
    final kept = <ChatMember>[];
    final seen = <String>{};
    for (final member in members) {
      final name = member.name.trim();
      final model = member.model.model.trim();
      if (!isSafeStorageId(member.id) || name.isEmpty || model.isEmpty) {
        continue;
      }
      if (!seen.add(member.id)) continue;
      kept.add(
        ChatMember(
          member.id,
          name,
          ChatModelRef(
            model,
            serverAddress: member.model.serverAddress,
            profileId: member.model.profileId,
            manualSource:
                member.model.manualSource ??
                (member.model.serverAddress == null &&
                        member.model.model == settings.model
                    ? _manualRef().manualSource
                    : null),
          ),
          systemPrompt: member.systemPrompt,
          avatarBase64: member.avatarBase64,
          personaId: member.personaId,
        ),
      );
    }
    final known = kept.map((member) => member.id).toSet();
    final selection = selectedIds.where(known.contains).toSet().toList();
    final id = activeId;
    if (id == null) {
      _writeRoom(null, members: kept, memberIds: selection);
    } else {
      final session = activeSession ?? await _ensureSession(id);
      if (session == null || _deletedSessions.contains(id)) return;
      _writeRoom(session, members: kept, memberIds: selection);
      // A running batch saves the session together with all its replies.
      if (!isStreaming(id)) await _sessionStore.saveSession(session);
    }
    _notifyNow();
  }

  Future<void> saveParticipant(ChatParticipant participant) async {
    final profile = ChatParticipant(
      id: participant.id,
      name: participant.name.trim(),
      configuration: participant.configuration.validated(),
      systemPrompt: participant.systemPrompt.trim(),
      personaId: participant.personaId,
      avatarBase64: participant.avatarBase64,
    );
    if (!isSafeStorageId(profile.id) || profile.name.isEmpty) {
      throw const FormatException('Model name and profile ID are required');
    }
    final previous = _participants.indexWhere((item) => item.id == profile.id);
    final next = [..._participants];
    if (previous < 0) {
      next.add(profile);
    } else {
      next[previous] = profile;
    }
    await _settingsStore.saveParticipants(next);
    _participants = next;
    _notifyNow();
  }

  Future<void> deleteParticipant(String id) async {
    final next = _participants.where((profile) => profile.id != id).toList();
    await _settingsStore.saveParticipants(next);
    _participants = next;
    _notifyNow();
  }

  SessionSummary? summaryFor(String id) {
    for (final summary in summaries) {
      if (summary.id == id) return summary;
    }
    return null;
  }

  void _sortSummaries() {
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _upsertSummary(ChatSession session) {
    if (_deletedSessions.contains(session.id)) return;
    final existing = summaryFor(session.id);
    if (existing != null) {
      existing
        ..title = session.title
        ..updatedAt = session.updatedAt;
    } else {
      summaries.add(session.toSummary());
    }
    _sortSummaries();
  }

  Future<void> selectSession(String id) async {
    if (_deletedSessions.contains(id)) return;
    if (activeId != id) {
      activeId = id;
      _notifyNow();
    }
    await _ensureSession(id);
  }

  Future<ChatSession?> _ensureSession(String id) async {
    if (_deletedSessions.contains(id)) return null;
    final cached = _cache[id];
    if (cached != null) return cached;
    return _sessionLoads.putIfAbsent(
      id,
      () => _loadSessionIntoCache(id).whenComplete(() {
        _sessionLoads.remove(id);
      }),
    );
  }

  Future<ChatSession?> _loadSessionIntoCache(String id) async {
    final loaded = await _sessionStore.loadSession(id);
    if (_disposed || _deletedSessions.contains(id)) return null;
    final cached = _cache[id];
    if (cached != null) return cached;
    if (loaded == null) return null;
    _cache[id] = loaded;
    _upsertSummary(loaded);
    _notifyNow();
    return loaded;
  }

  /// A new chat starts from the global selection, never from the room of the
  /// conversation that was just left.
  void newChat() {
    activeId = null;
    _nextMode = ChatMode.chat;
    _nextPersonas.clear();
    _nextModel = null;
    _nextMembers = const [];
    _nextMemberIds = const [];
    _notifyNow();
  }

  /// Adds an already-loaded session to the cache and opens it. Used by import
  /// flows and previews; persisting is the caller's responsibility.
  void restoreSession(ChatSession session) {
    _deletedSessions.remove(session.id);
    _cache[session.id] = session;
    _upsertSummary(session);
    activeId = session.id;
    _notifyNow();
  }

  Future<void> renameSession(String id, String title) async {
    _titleRequests.remove(id);
    if (summaryFor(id) == null) return;
    final session = _cache[id] ?? await _ensureSession(id);
    if (session == null || _deletedSessions.contains(id)) return;
    session
      ..title = title.trim()
      ..updatedAt = nowMs();
    _upsertSummary(session);
    await _sessionStore.saveSession(session);
    await _sessionStore.saveIndex(summaries);
    _notifyNow();
  }

  Future<void> deleteSession(String id) async {
    _requestDebug.removeWhere((record) => record.sessionId == id);
    _deletedSessions.add(id);
    for (final token in _streaming.remove(id) ?? <CancelToken>[]) {
      token.cancel('session deleted');
    }
    _cache.remove(id);
    summaries.removeWhere((summary) => summary.id == id);
    if (activeId == id) activeId = null;
    await _batchSaves[id];
    await _sessionStore.deleteSession(id);
    await _sessionStore.saveIndex(summaries);
    _notifyNow();
  }

  Future<void> deleteAllChats() async {
    _requestDebug.clear();
    _draftSaveTimer?.cancel();
    for (final id in _cache.keys) {
      _deletedSessions.add(id);
    }
    for (final summary in summaries) {
      _deletedSessions.add(summary.id);
    }
    for (final tokens in _streaming.values) {
      for (final token in tokens) {
        token.cancel('all chats deleted');
      }
    }
    _streaming.clear();
    _cache.clear();
    _titleRequests.clear();
    _drafts.clear();
    _draftFiles.clear();
    _nextModel = null;
    _nextMembers = const [];
    _nextMemberIds = const [];
    _nextMode = ChatMode.chat;
    _nextPersonas.clear();
    summaries.clear();
    activeId = null;
    await Future.wait(_batchSaves.values.toList());
    await _sessionStore.clearAll();
    _notifyNow();
  }

  // ---------------------------------------------------------------- sending

  Future<bool> sendMessage(String text, List<FileAttachment> files) async {
    if (activeStreaming) return false;
    final content = text.trim();
    if (content.isEmpty && files.isEmpty) return false;

    // Loading an uncached session can yield. Recheck the selection and batch
    // lock before resolving the room's recipients and changing the branch.
    final selectedSessionId = activeId;
    final draftToClear = draftKey;
    var session = activeSession;
    if (selectedSessionId != null && session == null) {
      session = await _ensureSession(selectedSessionId);
      if (activeId != selectedSessionId || activeStreaming || session == null) {
        return false;
      }
    }
    final targets = _targetsFor(content);
    if (!_canSend(targets, files)) return false;
    if (session == null) {
      final now = nowMs();
      session = ChatSession(
        id: newId(),
        createdAt: now,
        updatedAt: now,
        selectedParticipantIds: selectedParticipantIds,
        mode: _nextMode,
        chatPersonaId: _nextPersonas[ChatMode.chat],
        workPersonaId: _nextPersonas[ChatMode.work],
        // The first message turns the draft into the session, so the draft's
        // assistant model and room travel with it.
        model: _nextModel,
        members: _nextMembers,
        selectedMemberIds: _nextMemberIds,
      );
      // The draft is consumed here: a later new chat starts from the global
      // selection instead of inheriting this room.
      _nextMode = ChatMode.chat;
      _nextPersonas.clear();
      _nextModel = null;
      _nextMembers = const [];
      _nextMemberIds = const [];
      _cache[session.id] = session;
      activeId = session.id;
    }

    final main = targets.singleOrNull;
    if (session.model == null &&
        main != null &&
        main.participant == null &&
        main.reference.serverAddress != null) {
      session.model = main.reference;
    }
    final history = session.visibleMessages;
    final now = nowMs();
    final user = UserMessage(
      id: newId(),
      createdAt: now,
      content: content,
      files: List.of(files),
    );
    final responses = _createResponses(targets, now);
    appendBranch(session, history.lastOrNull?.id, [
      user,
      ...responses.map((response) => response.assistant),
    ]);
    _upsertSummary(session);
    unawaited(
      _runBatch(
        session: session,
        question: user,
        history: history,
        responses: responses,
        titleRequest: session.title.isEmpty,
      ),
    );
    _clearDraftKey(draftToClear);
    // Feedback runs immediately after the message is accepted; it never waits
    // for the reply stream, which keeps running in its own future.
    final accepted = onMessageAccepted;
    if (accepted != null && !_disposed) {
      unawaited(Future<void>.sync(accepted).catchError((Object _) {}));
    }
    // Let the queued feedback and the first streaming notification run before
    // the caller continues, so a caller that observes state right after this
    // future sees the same picture the UI does.
    await Future<void>.value();
    return true;
  }

  Future<bool> regenerate(String assistantId) async {
    if (activeStreaming) return false;
    final session = activeSession;
    if (session == null) return false;
    final visible = session.visibleMessages;
    final index = visible.indexWhere((message) => message.id == assistantId);
    if (index < 0 || visible[index] is! AssistantMessage) return false;
    final target = visible[index] as AssistantMessage;
    final original = _targetForReply(target);
    final userIndex = _userIndexForReply(visible, index);
    if (userIndex < 0 || original == null) return false;
    final user = visible[userIndex] as UserMessage;
    if (!_canSend([original], user.files)) return false;

    final responses = _createResponses([original], nowMs());
    // A retry copies nothing forward, so it starts empty and pending.
    _markPending(responses.single.assistant);
    // Copy the unaffected replies after this one. They remain visible in the
    // new version, while the old turn and all its descendants stay intact.
    final followingReplies = visible
        .skip(index + 1)
        .takeWhile((message) => message is AssistantMessage);
    appendBranch(session, target.parentId, [
      responses.single.assistant,
      for (final reply in followingReplies)
        ChatMessage.fromJson({...reply.toJson(), 'id': newId()})!,
    ]);
    _upsertSummary(session);
    unawaited(
      _runBatch(
        session: session,
        question: user,
        history: visible.sublist(0, userIndex),
        responses: responses,
      ),
    );
    return true;
  }

  Future<bool> editPrompt(
    String userMessageId,
    String content,
    List<FileAttachment> files,
  ) async {
    if (activeStreaming) return false;
    final session = activeSession;
    if (session == null) return false;
    final visible = session.visibleMessages;
    final index = visible.indexWhere((message) => message.id == userMessageId);
    if (index < 0 || visible[index] is! UserMessage) return false;
    final target = visible[index] as UserMessage;
    if (content.trim().isEmpty && files.isEmpty) return false;
    final targets = _targetsFor(content);
    if (!_canSend(targets, files)) return false;
    final now = nowMs();
    final user = UserMessage(
      id: newId(),
      createdAt: now,
      content: content.trim(),
      files: List.of(files),
    );
    final responses = _createResponses(targets, now);
    appendBranch(session, target.parentId, [
      user,
      ...responses.map((response) => response.assistant),
    ]);
    _upsertSummary(session);
    unawaited(
      _runBatch(
        session: session,
        question: user,
        history: visible.sublist(0, index),
        responses: responses,
      ),
    );
    return true;
  }

  Future<bool> continueReply([String? assistantId]) async {
    if (activeStreaming) return false;
    final session = activeSession;
    if (session == null) return false;
    final visible = session.visibleMessages;
    final index = assistantId == null
        ? visible.length - 1
        : visible.indexWhere((message) => message.id == assistantId);
    if (index < 0 || visible[index] is! AssistantMessage) return false;
    final reply = visible[index] as AssistantMessage;
    if (!reply.canContinue ||
        visible.skip(index + 1).any((message) => message is UserMessage)) {
      return false;
    }
    final userIndex = _userIndexForReply(visible, index);
    final target = _targetForReply(reply);
    if (userIndex < 0 || target == null) return false;

    final question = visible[userIndex] as UserMessage;
    if (!_canSend([target], question.files)) return false;
    _markPending(reply);
    unawaited(
      _runBatch(
        session: session,
        question: question,
        history: visible.sublist(0, userIndex),
        responses: [(assistant: reply, target: target)],
        continuation: true,
      ),
    );
    return true;
  }

  int _userIndexForReply(List<ChatMessage> visible, int replyIndex) {
    for (var i = replyIndex - 1; i >= 0; i--) {
      if (visible[i] is UserMessage) return i;
    }
    return -1;
  }

  /// Rebuilds the connection that produced [reply]. The stored reference is
  /// credential-free, so a retry or continuation reuses the same server and
  /// model instead of the model the user has selected since. History written
  /// before references existed keeps the legacy hand-filled behaviour.
  _ModelTarget? _targetForReply(AssistantMessage reply) {
    final id = reply.participantId;
    final profile = _participants.where((item) => item.id == id).firstOrNull;
    final stored = reply.modelReference;
    if (stored == null) {
      if (id != null && profile == null) return null;
      final configuration =
          profile?.configuration ?? settings.modelConfiguration;
      // Replies from before model references used the manual connection.
      return (
        configuration: configuration,
        participant: profile,
        reference: _modelRefFor(configuration, profile?.id),
      );
    }
    final name = reply.participantName;
    final identity = name == null || id == null
        ? profile
        : ChatParticipant(
            id: id,
            name: name,
            configuration:
                profile?.configuration ?? settings.modelConfiguration,
            systemPrompt: profile?.systemPrompt ?? '',
            personaId: profile?.personaId,
            avatarBase64: reply.participantAvatarBase64,
          );
    return _targetForModel(stored, identity: identity);
  }

  bool canReplyAs(AssistantMessage reply) {
    final target = _targetForReply(reply);
    final visible = activeSession?.visibleMessages;
    if (target == null || visible == null) return false;
    final replyIndex = visible.indexWhere((message) => message.id == reply.id);
    if (replyIndex < 0) return false;
    final userIndex = _userIndexForReply(visible, replyIndex);
    if (userIndex < 0) return false;
    // Only this reply's attachment batch matters here. The room's other
    // recipients may not be reachable, which is not this reply's problem.
    return target.configuration.apiKey.trim().isNotEmpty &&
        _fileBatchError((visible[userIndex] as UserMessage).files, [target]) ==
            null;
  }

  /// Marks an unfinished reply as pending before its request starts. Without
  /// this window a continuation shows its previous status, which the progress
  /// marker and the composer read. A continuation keeps the text that is
  /// already visible.
  void _markPending(AssistantMessage assistant, {AssistantMessage? answer}) {
    if (answer != null) {
      assistant.blocks = [...answer.blocks];
      assistant.latestReminder = answer.latestReminder;
      assistant.model = answer.model;
    }
    settleReply(assistant, ReplyStatus.pending, nowMs());
    _notifyNow();
  }

  List<({AssistantMessage assistant, _ModelTarget target})> _createResponses(
    List<_ModelTarget> targets,
    int now,
  ) => [
    for (final target in targets)
      (
        target: target,

        assistant: AssistantMessage(
          id: newId(),
          createdAt: now,
          model: target.configuration.model,
          participantId: target.participant?.id,
          participantName: target.participant?.name,
          participantAvatarBase64: target.participant?.avatarBase64,
          thinking: settings.thinking,
          search: settings.search,
          status: ReplyStatus.pending,
        ),
      ),
  ];

  bool _canSend(List<_ModelTarget> targets, List<FileAttachment> files) =>
      _hasConnection(targets) && _fileBatchError(files, targets) == null;

  void stopReply() {
    for (final token in _streaming[activeId] ?? <CancelToken>[]) {
      token.cancel('stopped by user');
    }
  }

  Future<void> switchVersion(String messageId) async {
    final session = activeSession;
    if (session == null || activeStreaming) return;
    selectVersion(session, messageId);
    session.updatedAt = nowMs();
    _upsertSummary(session);
    _notifyNow();
    await _sessionStore.saveSession(session);
    await _sessionStore.saveIndex(summaries);
  }

  Future<void> _runBatch({
    required ChatSession session,
    required UserMessage question,
    required List<ChatMessage> history,
    required List<({AssistantMessage assistant, _ModelTarget target})>
    responses,
    bool titleRequest = false,
    bool continuation = false,
  }) async {
    final tokens = List.generate(responses.length, (_) => CancelToken());
    _streaming[session.id] = tokens;
    if (titleRequest) _titleRequests.add(session.id);
    final shared =
        responses.any((response) => response.target.participant != null) ||
        history.whereType<AssistantMessage>().any(
          (reply) => reply.participantId != null,
        );
    final transcript = shared ? sharedGroupHistory(history) : history;
    final systems = [
      for (final response in responses) _systemFor(session, response.target),
    ];
    try {
      await Future.wait([
        for (var i = 0; i < responses.length; i++)
          _runRequest(
            session: session,
            question: responses.length > 1
                ? _copyRequestUser(question)
                : question,
            assistant: responses[i].assistant,
            target: responses[i].target,
            history: shared
                ? _historyForTarget(transcript, responses[i].target)
                : transcript,
            system: systems[i],
            titleRequest: titleRequest && i == 0,
            cancelToken: tokens[i],
            continuation: continuation,
          ),
      ]);
    } finally {
      // The batch is over even if another send replaced the map in between; a
      // leftover entry would report a finished conversation as busy forever.
      _streaming.remove(session.id);
      _titleRequests.remove(session.id);
      if (!_deletedSessions.contains(session.id)) {
        _fallbackTitle(session);
        session.updatedAt = nowMs();
        _upsertSummary(session);
        final save = _saveBatch(session);
        _batchSaves[session.id] = save;
        _flushNotify();
        await save;
        if (identical(_batchSaves[session.id], save)) {
          _batchSaves.remove(session.id);
        }
      }
    }
  }

  Future<void> _saveBatch(ChatSession session) async {
    try {
      await _sessionStore.saveSession(session);
      await _sessionStore.saveIndex(summaries);
    } catch (error) {
      debugPrint('Failed to save chat session: $error');
    }
  }

  // Providers mutate only their own attachment status/remote ID when parallel
  // requests prepare the same bytes. The underlying local content is shared.
  UserMessage _copyRequestUser(
    UserMessage user, {
    String? content,
    List<FileAttachment>? attachments,
  }) => UserMessage(
    id: user.id,
    createdAt: user.createdAt,
    content: content ?? user.content,
    files: [
      for (final file in attachments ?? user.files)
        FileAttachment(
          id: file.id,
          name: file.name,
          size: file.size,
          isImage: file.isImage,
          mimeType: file.mimeType,
          localPath: file.localPath,
          bytes: file.bytes,
        ),
    ],
  );

  List<ChatMessage> _historyForTarget(
    List<ChatMessage> transcript,
    _ModelTarget target,
  ) => [
    for (final message in transcript)
      if (message is UserMessage && message.files.isNotEmpty)
        _filterHistoricalAttachments(message, target)
      else
        message,
  ];

  UserMessage _filterHistoricalAttachments(
    UserMessage user,
    _ModelTarget target,
  ) {
    final available = <FileAttachment>[];
    final omitted = <String>[];
    for (final file in user.files) {
      if (_attachmentError(file.name, file.size, file.isImage, [target]) ==
          null) {
        available.add(file);
      } else {
        omitted.add(file.name);
      }
    }
    return _copyRequestUser(
      user,
      attachments: available,
      content: [
        if (user.content.isNotEmpty) user.content,
        for (final name in omitted)
          '[Earlier attachment unavailable for this model: $name]',
      ].join('\n\n'),
    );
  }

  _RequestSystem _systemFor(ChatSession session, _ModelTarget target) {
    // Keep the most stable text first: base, personas and workflows,
    // member profile and name, then the conversation mode.
    final participant = target.participant;
    final profilePrompt = participant?.systemPrompt.trim() ?? '';
    final linkedId = participant?.personaId;
    final linked = personaOptions.where((p) => p.id == linkedId).firstOrNull;
    final conversation = personaForId(session.personaId ?? settings.personaId);
    final applied = [
      ?linked,
      if (conversation.id != linked?.id &&
          (session.personaId != null ||
              (linked == null && profilePrompt.isEmpty)))
        conversation,
    ];
    final zh = settings.isZh;
    final base = settings.systemPromptOverride.trim();
    final promptText = [
      if (base.isNotEmpty) base else if (zh) systemPrompt else systemPromptEn,
      for (final persona in applied) ...[
        ?persona.prompt(zh),
        if (persona.workflow.isNotEmpty)
          [
            zh ? '按以下人格流程逐步作答：' : 'Follow this persona workflow in order:',
            for (final (i, step) in persona.workflow.indexed) '${i + 1}. $step',
          ].join('\n'),
      ],
      if (profilePrompt.isNotEmpty &&
          !applied.any((persona) => persona.prompt(zh)?.trim() == profilePrompt))
        profilePrompt,
      if (participant != null)
        zh
            ? '你在本对话中的名字是 ${participant.name}。之前的公开回复会标注作者名。'
            : 'Your name in this conversation is ${participant.name}. '
                  'Earlier public replies are labeled with their authors’ names.',
      if (session.mode == ChatMode.chat && participant != null)
        zh ? '像微信群里的朋友一样接话：回应刚才说的话，短一点，自然一点；表情符号偶尔用就好，不必每次都总结。' : 'Chat like a friend in a group chat: pick up what someone just said, keep it natural and brief, and use emoji sparingly. Skip the recap unless it helps.',
      if (session.mode == ChatMode.work)
        settings.isZh ? '围绕任务作答：先给结论或交付物，再列必要步骤、约束和待确认问题。简单问题简短回答，不虚构进度。' : 'Organize the answer around the task. Lead with the conclusion or deliverable, then list necessary steps, constraints, and open questions. Keep simple answers short and do not invent progress.',
    ].join('\n\n');
    return (prompt: promptText, personas: List.unmodifiable(applied));
  }

  Future<void> _runRequest({
    required ChatSession session,
    required UserMessage question,
    required AssistantMessage assistant,
    required _ModelTarget target,
    required List<ChatMessage> history,
    required _RequestSystem system,
    required bool titleRequest,
    required CancelToken cancelToken,
    required bool continuation,
  }) async {
    final configuration = target.configuration;
    final participant = target.participant;
    final record = _debugRecording
        ? ChatRequestDebug._(
            sessionId: session.id,
            model: configuration.model.trim(),
            protocol: configuration.protocol,
            participantName: participant?.name,
            personas: system.personas,
            systemPrompt: system.prompt,
          )
        : null;
    if (record != null) {
      if (_requestDebug.length == _debugLimit) _requestDebug.removeAt(0);
      _requestDebug.add(record);
    }
    final preservedBlocks = continuation ? assistant.blocks.length : 0;
    final nativePrefix =
        continuation &&
        participant == null &&
        (assistant.model == null || assistant.model == configuration.model);
    final prefix = !continuation
        ? null
        : nativePrefix
        ? assistant
        : AssistantMessage(
            id: assistant.id,
            createdAt: assistant.createdAt,
            blocks: [TextBlock(text: assistant.text)],
          );
    void finish(ReplyStatus status, {ReplyError? error}) {
      if (record != null) {
        record._status = status;
        final kind = error?.kind;
        record._errorKind = switch (kind) {
          null => null,
          'auth' ||
          'network' ||
          'interrupted' ||
          'protocol' ||
          'stream' ||
          'http' ||
          'configuration' ||
          'attachment' ||
          'unsupported' => kind,
          _ => 'other',
        };
        record._httpStatus = error?.status;
        record._errorMessage = error?.message;
      }
      settleReply(
        assistant,
        status,
        nowMs(),
        error: error,
        preserveBlockCount: preservedBlocks,
      );
    }

    if (configuration.apiKey.trim().isEmpty) {
      finish(
        ReplyStatus.error,
        error: ReplyError(
          kind: 'auth',
          message: '',
          localMessage: settings.isZh
              ? '请登录或配置 API，再选择已连接的模型。'
              : 'Sign in or configure an API, then select a connected model.',
        ),
      );
      _notifyNow();
      return;
    }

    assistant
      ..status = ReplyStatus.streaming
      ..model = configuration.model
      ..modelReference = target.reference
      ..stopReason = null
      ..stopDetails = null
      ..error = null;
    final blockIndexes = <int, int>{};
    var completedNormally = false;
    _notifyNow();

    try {
      final reminder = prefix?.latestReminder ?? createLatestReminder();
      assistant.latestReminder = reminder;

      await for (final event in _gateway.stream(
        configuration: configuration,
        request: ChatRequest(
          history: history,
          question: question,
          prefix: prefix,
          systemPrompt: system.prompt,
          thinking: assistant.thinking,
          search: assistant.search,
          titleRequest: titleRequest,
          latestReminder: reminder,
        ),
        cancelToken: cancelToken,
        onAttachmentChanged: _notifyStreaming,
        // An account token must reach the server the user signed in to. A
        // redirect could hand it to another host, so account requests never
        // follow one; hand-filled endpoints keep the existing behaviour.
        followRedirects: target.reference.serverAddress == null,
      )) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (event is MessageDeltaEvent) {
          final title = event.title?.trim() ?? '';
          if (title.isNotEmpty &&
              _titleRequests.contains(session.id) &&
              titleRequest &&
              session.title.isEmpty &&
              !cancelToken.isCancelled &&
              (event.stopReason == StopReason.endTurn ||
                  event.stopReason == StopReason.maxTokens)) {
            session.title = title;
            _titleRequests.remove(session.id);
            _upsertSummary(session);
            _notifyNow();
          }
        }
        applyApiEvent(assistant, event, nowMs(), blockIndexes);
        _notifyStreaming();
      }
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      finish(ReplyStatus.done);
      completedNormally = true;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        finish(ReplyStatus.stopped);
      } else {
        finish(
          ReplyStatus.error,
          error: ReplyError(
            kind: 'network',
            message: error.message ?? '',
            localMessage: _localErrorMessage('network'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (error.kind == 'interrupted' && assistant.stopReason != null) {
        // The final stop event was lost; the reply is still complete.
        finish(ReplyStatus.done);
      } else {
        finish(
          ReplyStatus.error,
          error: ReplyError(
            kind: error.kind,
            message: error.message,
            status: error.status,
            localMessage: _localErrorMessage(error.kind, status: error.status),
          ),
        );
      }
    } catch (error) {
      finish(
        ReplyStatus.error,
        error: ReplyError(
          kind: 'protocol',
          message: error.toString(),
          localMessage: _localErrorMessage('protocol'),
        ),
      );
    } finally {
      _notifyStreaming();
    }

    final deliver = onReplyDelivered;
    if (completedNormally &&
        deliver != null &&
        !_disposed &&
        identical(activeSession, session) &&
        assistant.blocks
            .skip(preservedBlocks)
            .whereType<TextBlock>()
            .any(
              (block) => !block.isTemplate && block.text.trim().isNotEmpty,
            ) &&
        session.visibleMessages.contains(assistant)) {
      // Audio is optional feedback, not part of the request's outcome.
      unawaited(Future<void>.sync(deliver).catchError((Object _) {}));
    }
  }

  String? _localErrorMessage(String kind, {int? status}) {
    final zh = settings.isZh;
    if (status == 413) {
      return zh
          ? '请求超过服务端大小限制。请缩短消息、减少附件，或开启新对话后重试。'
          : 'The request is too large for this server. Shorten the message, remove attachments, or start a new chat.';
    }
    return switch (kind) {
      'network' =>
        zh
            ? '网络连接失败，请检查网络后重试'
            : 'Network error. Check your connection and try again.',
      'interrupted' =>
        zh ? '连接中断，请重试' : 'The connection was interrupted. Try again.',
      'protocol' =>
        zh
            ? '模型服务返回了异常响应，请重试。'
            : 'The service returned an unexpected response. Try again.',
      _ => null,
    };
  }

  /// Uses the first prompt as a title when the server does not return one.
  void _fallbackTitle(ChatSession session) {
    if (session.title.isNotEmpty) return;
    for (final message in session.visibleMessages) {
      if (message is! UserMessage) continue;
      var text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) continue;
      if (text.length > 30) {
        text = '${text.substring(0, 30)}…';
      }
      session.title = text;
      return;
    }
  }

  String createLatestReminder() {
    final now = DateTime.now();
    String pad(int value) => value.toString().padLeft(2, '0');
    final date = '${now.year}-${pad(now.month)}-${pad(now.day)}';
    final weekday = settings.isZh
        ? const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][now.weekday -
              1]
        : const [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday',
          ][now.weekday - 1];
    final parts = [
      date,
      weekday,
      settings.locationName.trim(),
      'Web',
      settings.isZh ? '中文' : 'English',
    ];
    return parts.join(',');
  }

  // --------------------------------------------------------------- settings

  Future<void> setAdvancedMode(bool value) async {
    await _settingsStore.setAdvancedMode(value);
    settings.isAdvancedMode = value;
    _notifyNow();
  }

  Future<void> setApiKey(String value) async {
    await saveModelConfiguration(
      settings.modelConfiguration.copyWith(apiKey: value.trim()),
    );
  }

  Future<void> setLocale(String value) async {
    settings.locale = value;
    await _settingsStore.setLocale(value);
    _notifyNow();
  }

  Future<void> setThemePreference(String value) async {
    settings.themePreference = value;
    await _settingsStore.setThemePreference(value);
    _notifyNow();
  }

  Future<void> setLocationName(String value) async {
    settings.locationName = value;
    await _settingsStore.setLocationName(value);
    _notifyNow();
  }

  Future<void> setThinking(bool value) async {
    settings.thinking = value;
    await _settingsStore.setThinking(value);
    _notifyNow();
  }

  Future<void> setSearch(bool value) async {
    settings.search = value;
    await _settingsStore.setSearch(value);
    _notifyNow();
  }

  Future<void> setChatBackground(ChatBackground value) async {
    await _settingsStore.setChatBackground(value);
    settings.chatBackground = value;
    _notifyNow();
  }

  /// The imported background picture, or null to fall back to the preset.
  Future<void> setChatBackgroundImage(String? base64) async {
    final image = base64 == null || base64.isEmpty ? null : base64;
    await _settingsStore.setChatBackgroundImage(image);
    settings.chatBackgroundImageBase64 = image;
    _notifyNow();
  }

  /// Whether chat conversations share memory across sessions.
  Future<void> setMemorySync(bool value) async {
    await _settingsStore.setMemorySync(value);
    settings.memorySync = value;
    _notifyNow();
  }

  Future<void> setSystemPrompt(String value) async {
    final prompt = value.trim();
    await _settingsStore.setSystemPrompt(prompt);
    settings.systemPromptOverride = prompt;
    _notifyNow();
  }

  Future<void> setPersona(String value) async {
    settings.personaId = value;
    await _settingsStore.setPersona(value);
    _notifyNow();
  }

  Future<void> setSiderCollapsed(bool value) async {
    settings.siderCollapsed = value;
    await _settingsStore.setSiderCollapsed(value);
    _notifyNow();
  }

  Future<void> setApiOrigin(String value) async {
    await saveModelConfiguration(
      settings.modelConfiguration.copyWith(apiOrigin: value),
    );
  }

  /// Saves the server the user signed in to. Only the address is persisted; the
  /// token stays in [account]. Pointing the app at a different server revokes
  /// the in-memory session immediately, so no request can keep using a token
  /// against an address the user no longer chose.
  Future<void> setServerAddress(String value) async {
    final address = value.trim();
    await _settingsStore.setServerAddress(address);
    settings.serverAddress = address;
    if (account.address != null && account.address != _serverAddress) {
      account.clearSession();
    }
    _notifyNow();
  }

  Future<void> saveModelConfiguration(ModelConfiguration value) async {
    final configuration = value.validated();
    await _settingsStore.saveModelConfiguration(configuration);
    settings.modelConfiguration = configuration;
    api.origin = configuration.apiOrigin;
    _notifyNow();
  }

  Future<void> verifyModelConfiguration(ModelConfiguration value) =>
      _gateway.verify(value);

  Future<void> verifyApiKey(String key) => verifyModelConfiguration(
    settings.modelConfiguration.copyWith(apiKey: key.trim()),
  );

  // ----------------------------------------------------------------- drafts

  String get draftKey => activeId ?? '__new__';

  String get draftText => _drafts[draftKey] ?? '';

  void setDraftText(String text) {
    if (text.isEmpty) {
      _drafts.remove(draftKey);
    } else {
      _drafts[draftKey] = text;
    }
    _scheduleDraftSave();
  }

  List<FileAttachment> get draftFiles =>
      _draftFiles.putIfAbsent(draftKey, () => []);

  Future<String?> addDraftFiles(List<PickedFileInfo> picked) async {
    final current = draftFiles;
    final zh = settings.isZh;
    if (current.length + picked.length > maxFileCount) {
      return zh
          ? '最多可添加 $maxFileCount 个文件'
          : 'Up to $maxFileCount files can be attached';
    }
    // Validate the whole batch before copying anything to disk.
    final targets = _targetsFor(draftText);
    for (final item in picked) {
      final error = _attachmentError(
        item.name,
        item.size,
        isImageMime(lookupMimeType(item.name) ?? ''),
        targets,
      );
      if (error != null) return error;
    }

    final files = <FileAttachment>[];
    try {
      for (final item in picked) {
        final mime = lookupMimeType(item.name) ?? '';
        final isImage = isImageMime(mime);
        files.add(
          item.bytes != null
              ? await _sessionStore.importAttachmentBytes(
                  bytes: item.bytes!,
                  name: item.name,
                  size: item.size,
                  isImage: isImage,
                  mimeType: mime,
                )
              : await _sessionStore.importAttachment(
                  sourcePath: item.path!,
                  name: item.name,
                  size: item.size,
                  isImage: isImage,
                  mimeType: mime,
                ),
        );
      }
    } catch (error) {
      for (final file in files) {
        await _sessionStore.deleteAttachmentFile(file);
      }
      return zh ? '读取文件失败：$error' : 'Failed to read file: $error';
    }
    current.addAll(files);
    _notifyNow();
    _scheduleDraftSave();
    return null;
  }

  String? draftAttachmentError(List<FileAttachment> files, {String? text}) =>
      _fileBatchError(files, _targetsFor(text ?? draftText));

  String? _fileBatchError(
    List<FileAttachment> files,
    List<_ModelTarget> targets,
  ) {
    if (files.length > maxFileCount) {
      return settings.isZh
          ? '最多可添加 $maxFileCount 个文件'
          : 'Up to $maxFileCount files can be attached';
    }
    for (final file in files) {
      final error = _attachmentError(
        file.name,
        file.size,
        file.isImage,
        targets,
      );
      if (error != null) return error;
    }
    return null;
  }

  String? _attachmentError(
    String name,
    int size,
    bool isImage,
    List<_ModelTarget> targets,
  ) {
    final zh = settings.isZh;
    for (final target in targets) {
      final configuration = target.configuration;
      final recipient = target.participant;
      final prefix = recipient == null ? '' : '${recipient.name}: ';
      final supportError = attachmentSupportError(
        name,
        configuration,
        isZh: zh,
      );
      if (supportError != null) return '$prefix$supportError';
      final limit = maxSizeMbFor(name, isImage, configuration: configuration);
      if (size > limit * 1024 * 1024) {
        return zh
            ? '$prefix$name 超过 ${limit}MB'
            : '$prefix$name exceeds ${limit}MB';
      }
    }
    return null;
  }

  Future<void> removeDraftFile(String id) async {
    final file = draftFiles.where((item) => item.id == id).firstOrNull;
    if (file == null) return;
    draftFiles.remove(file);
    await _sessionStore.deleteAttachmentFile(file);
    _notifyNow();
    _scheduleDraftSave();
  }

  void clearDraft() => _clearDraftKey(draftKey);

  void _clearDraftKey(String key) {
    _drafts.remove(key);
    _draftFiles.remove(key);
    _notifyNow();
    _scheduleDraftSave();
  }

  Future<void> _loadDrafts() async {
    final data = await _sessionStore.loadDrafts();
    final texts = data['texts'];
    if (texts is Map) {
      for (final entry in texts.entries) {
        if (entry.key is String && entry.value is String) {
          _drafts[entry.key as String] = entry.value as String;
        }
      }
    }
    final files = data['files'];
    if (files is Map) {
      for (final entry in files.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        final attachments = <FileAttachment>[];
        for (final item in entry.value as List) {
          final attachment = FileAttachment.fromJson(item);
          if (attachment != null) attachments.add(attachment);
        }
        if (attachments.isNotEmpty) {
          _draftFiles[entry.key as String] = attachments;
        }
      }
    }
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) {
        unawaited(_sessionStore.saveDrafts(_draftsJson()));
      }
    });
  }

  Map<String, dynamic> _draftsJson() => {
    'texts': Map<String, String>.from(_drafts),
    'files': {
      for (final entry in _draftFiles.entries)
        if (entry.value.isNotEmpty)
          entry.key: entry.value.map((file) => file.toJson()).toList(),
    },
  };

  // ------------------------------------------------------------- listeners

  void _notifyStreaming() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 60), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _flushNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _notifyNow();
  }

  void _notifyNow() {
    if (_disposed) return;
    _workspaceChanges.value++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    account.removeListener(_notifyNow);
    _notifyTimer?.cancel();
    _draftSaveTimer?.cancel();
    unawaited(_sessionStore.saveDrafts(_draftsJson()));
    for (final tokens in _streaming.values) {
      for (final token in tokens) {
        token.cancel('controller disposed');
      }
    }
    account.dispose();
    _workspaceChanges.dispose();
    super.dispose();
  }
}
