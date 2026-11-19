import 'dart:convert';

/// A conversation persona.
///
/// Built-in personas ship with Chinese and English copy. Custom personas
/// reuse one name and prompt for both languages, and may legitimately have an
/// empty prompt — the default assistant has none, and so can any copy of it.
class Persona {
  const Persona({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.descriptionZh,
    required this.descriptionEn,
    this.promptZh,
    this.promptEn,
    this.workflow = const [],
    this.isCustom = false,
  });

  /// Builds a custom persona. [name] is required; [systemPrompt] may be empty.
  factory Persona.custom({
    required String id,
    required String name,
    String systemPrompt = '',
    List<String> workflow = const [],
  }) {
    final title = name.trim();
    if (title.isEmpty) {
      throw const FormatException('Persona name is required');
    }
    final prompt = systemPrompt.trim();
    return Persona(
      id: id,
      nameZh: title,
      nameEn: title,
      descriptionZh: prompt,
      descriptionEn: prompt,
      promptZh: prompt,
      promptEn: prompt,
      workflow: List.unmodifiable(
        workflow.map((step) => step.trim()).where((s) => s.isNotEmpty),
      ),
      isCustom: true,
    );
  }

  /// Copies [source] into a new custom persona with a fresh [id].
  ///
  /// This is how editing a built-in persona works: the built-in entry stays
  /// untouched and the user gets an editable copy instead.
  factory Persona.copyOf(
    Persona source, {
    required String id,
    required String name,
    required String systemPrompt,
    required List<String> workflow,
  }) => Persona.custom(
    id: id,
    name: name,
    systemPrompt: systemPrompt,
    workflow: workflow,
  );

  final String id;
  final String nameZh;
  final String nameEn;
  final String descriptionZh;
  final String descriptionEn;
  final String? promptZh;
  final String? promptEn;
  final List<String> workflow;
  final bool isCustom;

  String name(bool zh) => zh ? nameZh : nameEn;
  String description(bool zh) => zh ? descriptionZh : descriptionEn;
  String? prompt(bool zh) => zh ? promptZh : promptEn;

  /// The portable v1 payload. `system_prompt` is always present, possibly
  /// empty, so a prompt-less persona survives the round trip.
  Map<String, Object> _portableFields(bool zh) => {
    'version': currentVersion,
    'name': name(zh),
    'system_prompt': prompt(zh) ?? '',
    if (workflow.isNotEmpty) 'workflow': workflow,
  };

  String exportJson({required bool zh}) =>
      const JsonEncoder.withIndent('  ').convert(_portableFields(zh));

  Map<String, Object> toStorageJson() => {'id': id, ..._portableFields(true)};

  static const int currentVersion = 1;

  static Persona importJson(String source, {required String id}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Persona JSON is not valid JSON');
    }
    return _fromFields(decoded, id);
  }

  static Persona? fromStorageJson(Object? value) {
    if (value is! Map || value['id'] is! String) return null;
    final id = value['id'] as String;
    if (id.isEmpty) return null;
    try {
      return _fromFields(value, id);
    } on FormatException {
      return null;
    }
  }

  /// Reads version 1 fields. `system_prompt` and `workflow` are optional;
  /// a missing prompt means an empty one.
  static Persona _fromFields(Object? value, String id) {
    if (value is! Map) {
      throw const FormatException('Persona JSON must be an object');
    }
    final version = value['version'];
    if (version != currentVersion) {
      throw const FormatException('Unsupported persona format');
    }
    final name = value['name'];
    final prompt = value['system_prompt'] ?? '';
    final steps = value['workflow'] ?? const <Object?>[];
    if (name is! String || prompt is! String || steps is! List) {
      throw const FormatException('Invalid persona fields');
    }
    if (steps.any((step) => step is! String)) {
      throw const FormatException('Invalid persona workflow');
    }
    return Persona.custom(
      id: id,
      name: name,
      systemPrompt: prompt,
      workflow: steps.cast<String>(),
    );
  }
}

const List<Persona> personas = [
  Persona(
    id: 'default',
    nameZh: '默认助手',
    nameEn: 'Default assistant',
    descriptionZh: '均衡、直接，适合大多数日常对话与问题。',
    descriptionEn: 'Balanced and direct, suitable for most conversations.',
  ),
  Persona(
    id: 'engineer',
    nameZh: '严谨工程师',
    nameEn: 'Rigorous engineer',
    descriptionZh: '优先给出可运行的实现、明确的工程取舍和边界条件。',
    descriptionEn:
        'Prefers runnable implementations, explicit trade-offs and edge cases.',
    promptZh: '回答时优先给出可运行的实现和明确的工程取舍，指出边界条件与潜在问题。',
    promptEn: 'Prefer runnable implementations and explicit engineering trade-offs. Call out edge cases and risks.',
  ),
  Persona(
    id: 'companion',
    nameZh: '温柔陪伴',
    nameEn: 'Gentle companion',
    descriptionZh: '语气温和、简洁，先理解感受，再给出建议。',
    descriptionEn:
        'A warm, concise tone that acknowledges feelings before advice.',
    promptZh: '用温和、简洁的语气回答，先理解对方的感受，再给出建议。',
    promptEn: 'Use a warm, concise tone. Acknowledge the feeling first, then offer suggestions.',
  ),
];

Persona personaById(String id) {
  for (final persona in personas) {
    if (persona.id == id) return persona;
  }
  return personas.first;
}
