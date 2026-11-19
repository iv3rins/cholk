import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/storage/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the original DeepSeek connection without discarding preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'deepseek_chat:api-key': 'legacy-key',
        'deepseek_chat:api-origin': 'https://proxy.example/base',
        'deepseek_chat:theme-preference': 'system',
        'deepseek_chat:locale': 'en-US',
        'deepseek_chat:persona': 'engineer',
      });

      final settings = await SettingsStore().load();
      expect(settings.protocol, ApiProtocol.deepseek);
      expect(settings.apiKey, 'legacy-key');
      expect(settings.apiOrigin, 'https://proxy.example/base');
      expect(settings.model, defaultModel);
      expect(settings.themePreference, 'system');
      expect(settings.locale, 'en-US');
      expect(settings.personaId, 'engineer');
    },
  );

  test(
    'restores one consistent model connection and capability record',
    () async {
      SharedPreferences.setMockInitialValues({
        'deepseek_chat:api-key': 'old-key',
        'deepseek_chat:api-origin': 'https://old.example',
      });
      final store = SettingsStore();
      const configuration = ModelConfiguration(
        protocol: ApiProtocol.openaiCompatible,
        apiOrigin: 'https://provider.example/v1',
        apiKey: 'new-key',
        model: 'audio-model',
        supportsImages: false,
        supportsPdf: false,
        supportsAudio: true,
      );
      await store.saveModelConfiguration(configuration);
      final restored = (await store.load()).modelConfiguration;
      expect(restored.toJson(), configuration.toJson());
      // Compatibility setters must update the same record after migration.
      await store.setApiKey('updated-key');
      await store.setApiOrigin('https://new.example/v1');
      final updated = await store.load();
      expect(updated.apiKey, 'updated-key');
      expect(updated.apiOrigin, 'https://new.example/v1');
      expect(updated.supportsAudio, isTrue);
      expect(updated.model, 'audio-model');
    },
  );

  test('persists only the server address for an account connection', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    expect((await store.load()).serverAddress, '');
    await store.setServerAddress(' https://accounts.example/ ');
    final settings = await store.load();
    expect(settings.serverAddress, 'https://accounts.example/');
  });

  test('invalid JSON falls back to the existing legacy connection', () async {
    SharedPreferences.setMockInitialValues({
      'deepseek_chat:api-key': 'legacy-key',
      'deepseek_chat:model-configuration': '{broken',
    });
    expect((await SettingsStore().load()).apiKey, 'legacy-key');
  });
}
