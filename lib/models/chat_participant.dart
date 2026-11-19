import 'model_configuration.dart';

/// One model participant and its saved display identity.
class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.name,
    required this.configuration,
    this.systemPrompt = '',
    this.personaId,
    this.avatarBase64,
  });

  final String id;
  final String name;
  final ModelConfiguration configuration;
  final String systemPrompt;
  final String? personaId;
  final String? avatarBase64;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'configuration': configuration.toJson(),
    'system_prompt': systemPrompt,
    if (personaId != null) 'persona_id': personaId,
    if (avatarBase64 != null) 'avatar_base64': avatarBase64,
  };

  static ChatParticipant? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['configuration'] is! Map) {
      return null;
    }
    final id = value['id'] as String;
    final name = value['name'] as String;
    if (id.isEmpty || name.trim().isEmpty) return null;
    return ChatParticipant(
      id: id,
      name: name,
      configuration: ModelConfiguration.fromJson(value['configuration']),
      systemPrompt: value['system_prompt'] is String
          ? value['system_prompt'] as String
          : '',
      personaId: value['persona_id'] is String
          ? value['persona_id'] as String
          : null,
      avatarBase64: value['avatar_base64'] is String
          ? value['avatar_base64'] as String
          : null,
    );
  }
}
