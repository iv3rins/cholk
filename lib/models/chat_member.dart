/// A credential-free reference to a configured model.
class ChatModelRef {
  const ChatModelRef(
    this.model, {
    this.serverAddress,
    this.profileId,
    this.manualSource,
  });

  final String model;
  final String? serverAddress;
  final String? profileId;
  final String? manualSource;

  Map<String, Object> toJson() => {
    'model': model,
    'server_address': ?serverAddress,
    'profile_id': ?profileId,
    'manual_source': ?manualSource,
  };

  static ChatModelRef? fromJson(Object? value) {
    if (value is! Map || value['model'] is! String) return null;
    final model = (value['model'] as String).trim();
    if (model.isEmpty) return null;
    final server = value['server_address'];
    final profile = value['profile_id'];
    final manual = value['manual_source'];
    if (server is String &&
        server.isNotEmpty &&
        profile == null &&
        manual == null) {
      return ChatModelRef(model, serverAddress: server);
    }
    if (server == null &&
        manual is String &&
        manual.isNotEmpty &&
        (profile == null || profile is String)) {
      return ChatModelRef(
        model,
        manualSource: manual,
        profileId: profile as String?,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatModelRef &&
      other.model == model &&
      other.serverAddress == serverAddress &&
      other.profileId == profileId &&
      other.manualSource == manualSource;

  @override
  int get hashCode =>
      Object.hash(model, serverAddress, profileId, manualSource);
}

/// A room-only member. Its identity is complete on its own: it never borrows a
/// system prompt, avatar or persona from a global participant, because a member
/// may exist without any global profile behind it.
class ChatMember {
  const ChatMember(
    this.id,
    this.name,
    this.model, {
    this.systemPrompt = '',
    this.avatarBase64,
    this.personaId,
  });

  final String id;
  final String name;
  final ChatModelRef model;

  /// The persona prompt this member speaks with in its room.
  final String systemPrompt;
  final String? avatarBase64;
  final String? personaId;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'model_ref': model.toJson(),
    'system_prompt': systemPrompt,
    'avatar_base64': ?avatarBase64,
    'persona_id': ?personaId,
  };

  static ChatMember? fromJson(Object? value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String)
      return null;
    final model = ChatModelRef.fromJson(value['model_ref']);
    if (model == null || (value['name'] as String).trim().isEmpty) return null;
    return ChatMember(
      value['id'] as String,
      value['name'] as String,
      model,
      // Records written before these fields existed keep their defaults.
      systemPrompt: value['system_prompt'] is String
          ? value['system_prompt'] as String
          : '',
      avatarBase64: value['avatar_base64'] is String
          ? value['avatar_base64'] as String
          : null,
      personaId: value['persona_id'] is String
          ? value['persona_id'] as String
          : null,
    );
  }
}
