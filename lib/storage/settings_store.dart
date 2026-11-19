import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/chat_member.dart';
import '../models/chat_participant.dart';
import '../models/chat_preferences.dart';
import '../models/model_configuration.dart';
import '../models/persona.dart';

// Preserve the original import for callers while keeping models free of I/O.
export '../models/app_settings.dart';

class SettingsStore {
  static const _kAdvancedMode = 'deepseek_chat:advanced-mode';
  static const _kApiKey = 'deepseek_chat:api-key';
  static const _kServerAddress = 'deepseek_chat:server-address';
  static const _kLocale = 'deepseek_chat:locale';
  static const _kTheme = 'deepseek_chat:theme-preference';
  static const _kLocation = 'deepseek_chat:location';
  static const _kThinking = 'deepseek_chat:thinking';
  static const _kSearch = 'deepseek_chat:search';
  static const _kSider = 'deepseek_chat:sider-collapsed';
  static const _kTtsVoice = 'deepseek_chat:tts-voice';
  static const _kPersona = 'deepseek_chat:persona';
  static const _kBackground = 'deepseek_chat:chat-background';
  static const _kBackgroundImage = 'deepseek_chat:chat-background-image';
  static const _kMemorySync = 'deepseek_chat:memory-sync';
  static const _kSystemPrompt = 'deepseek_chat:system-prompt';
  static const _kApiOrigin = 'deepseek_chat:api-origin';
  static const _kModelConfiguration = 'deepseek_chat:model-configuration';
  static const _kParticipants = 'deepseek_chat:participants';
  static const _kCustomPersonas = 'deepseek_chat:custom-personas';
  static const _kChatModel = 'deepseek_chat:chat-model';

  Future<List<Persona>> loadPersonas() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kCustomPersonas);
    if (saved == null) return const [];
    try {
      final data = jsonDecode(saved);
      if (data is! List) return const [];
      final ids = {for (final persona in personas) persona.id};
      return [
        for (final entry in data)
          if (Persona.fromStorageJson(entry) case final persona?)
            if (ids.add(persona.id)) persona,
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> savePersonas(List<Persona> values) => _saveString(
    _kCustomPersonas,
    jsonEncode([for (final persona in values) persona.toStorageJson()]),
  );

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString(_kLocale);
    final theme = prefs.getString(_kTheme);
    final origin = prefs.getString(_kApiOrigin);
    final settings = AppSettings(
      isAdvancedMode: prefs.getBool(_kAdvancedMode) ?? false,
      apiKey: prefs.getString(_kApiKey) ?? '',
      serverAddress: prefs.getString(_kServerAddress) ?? defaultAccountOrigin,
      locale: locale == 'en-US' ? 'en-US' : 'zh-CN',
      themePreference: {'dark', 'light', 'system'}.contains(theme)
          ? theme!
          : 'light',
      locationName: prefs.getString(_kLocation) ?? '',
      thinking: prefs.getBool(_kThinking) ?? false,
      search: prefs.getBool(_kSearch) ?? false,
      siderCollapsed: prefs.getBool(_kSider) ?? false,
      ttsVoice: prefs.getString(_kTtsVoice) == 'tide' ? 'tide' : 'stella',
      personaId: prefs.getString(_kPersona) ?? 'default',
      chatBackground: ChatBackground.fromWire(prefs.getString(_kBackground)),
      chatBackgroundImageBase64: switch (prefs.getString(_kBackgroundImage)) {
        final image? when image.isNotEmpty => image,
        _ => null,
      },
      memorySync: prefs.getBool(_kMemorySync) ?? false,
      systemPromptOverride: prefs.getString(_kSystemPrompt) ?? '',
      apiOrigin: origin != null && origin.trim().isNotEmpty
          ? origin.trim()
          : defaultApiOrigin,
    );
    final chatModel = prefs.getString(_kChatModel);
    if (chatModel != null) {
      try {
        settings.preferredChatModel = ChatModelRef.fromJson(
          jsonDecode(chatModel),
        );
      } on FormatException {
        // An unreadable preference leaves the default model in place.
      }
    }
    final saved = prefs.getString(_kModelConfiguration);
    if (saved != null) {
      try {
        settings.modelConfiguration = ModelConfiguration.fromJson(
          jsonDecode(saved),
        );
      } on FormatException {
        // An unreadable new record leaves the legacy connection available.
      }
    }
    return settings;
  }

  /// One record keeps protocol, endpoint, model and key in the same revision.
  Future<void> saveModelConfiguration(ModelConfiguration value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _kModelConfiguration,
      jsonEncode(value.toJson()),
    );
    if (!saved) throw StateError('Could not save API configuration');
  }

  Future<List<ChatParticipant>> loadParticipants() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kParticipants);
    if (saved == null) return const [];
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! List) return const [];
      final ids = <String>{};
      return [
        for (final record in decoded)
          if (ChatParticipant.fromJson(record) case final participant?)
            if (ids.add(participant.id)) participant,
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveParticipants(List<ChatParticipant> participants) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _kParticipants,
      jsonEncode([
        for (final participant in participants) participant.toJson(),
      ]),
    );
    if (!saved) throw StateError('Could not save chat participants');
  }

  Future<void> setAdvancedMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_kAdvancedMode, value)) {
      throw StateError('Could not save app mode');
    }
  }

  Future<void> setApiKey(String value) async {
    final settings = await load();
    await saveModelConfiguration(
      settings.modelConfiguration.copyWith(apiKey: value),
    );
  }

  Future<void> setServerAddress(String value) =>
      _saveString(_kServerAddress, value.trim());

  /// Stores the credential-free model reference, never the connection itself.
  Future<void> setChatModel(ChatModelRef? value) async {
    if (value == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kChatModel);
      return;
    }
    await _saveString(_kChatModel, jsonEncode(value.toJson()));
  }

  Future<void> setLocale(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, value);
  }

  Future<void> setThemePreference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, value);
  }

  Future<void> setLocationName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocation, value);
  }

  Future<void> setThinking(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kThinking, value);
  }

  Future<void> setSearch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSearch, value);
  }

  Future<void> setSiderCollapsed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSider, value);
  }

  Future<void> setTtsVoice(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTtsVoice, value);
  }

  Future<void> setChatBackground(ChatBackground value) =>
      _saveString(_kBackground, value.name);

  /// Removes the key rather than storing an empty string, so "no picture" reads
  /// back as null and the preset background applies again.
  Future<void> setChatBackgroundImage(String? base64) async {
    if (base64 == null || base64.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kBackgroundImage);
      return;
    }
    await _saveString(_kBackgroundImage, base64);
  }

  Future<void> setMemorySync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_kMemorySync, value)) {
      throw StateError('Could not save memory sync preference');
    }
  }

  Future<void> setSystemPrompt(String value) =>
      _saveString(_kSystemPrompt, value);

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not save preference: $key');
    }
  }

  Future<void> setPersona(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPersona, value);
  }

  Future<void> setApiOrigin(String value) async {
    final settings = await load();
    await saveModelConfiguration(
      settings.modelConfiguration.copyWith(apiOrigin: value),
    );
  }
}
