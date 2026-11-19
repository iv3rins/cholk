import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_participant.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/storage/settings_store.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/persona/persona_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _fill(WidgetTester tester, String key, String text) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('profiles can be created, edited and deleted in compact layout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatController()..settings.isAdvancedMode = true;
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        builder: (context, child) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) => AppScope(
            controller: controller,
            strings: const S(false),
            palette: darkPalette,
            child: child!,
          ),
        ),
        home: const PersonaPage(),
      ),
    );

    await tester.tap(find.byKey(const Key('add-participant')));
    await tester.pumpAndSettle();
    expect(find.text('Add model'), findsOneWidget);
    expect(find.text('Choose avatar'), findsOneWidget);
    final prompt = find.byKey(const Key('participant-prompt'));
    expect(tester.widget<TextFormField>(prompt).controller!.text, isEmpty);
    await _fill(tester, 'participant-name', 'Atlas');
    await _fill(tester, 'api-key', 'atlas-test-key');
    await _fill(tester, 'api-model', 'atlas-chat');
    await tester.tap(find.byKey(const Key('participant-save')));
    await tester.pumpAndSettle();

    final created = controller.participants.single;
    expect(created.systemPrompt, isEmpty);
    expect(created.configuration.model, 'atlas-chat');
    expect(controller.settings.apiKey, isEmpty);
    expect(find.text('AT'), findsOneWidget);

    final row = find.byKey(ValueKey('participant-${created.id}'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Edit model'), findsOneWidget);
    await _fill(tester, 'participant-name', 'Orchid');
    await _fill(tester, 'participant-prompt', 'Respond in short paragraphs.');
    await tester.tap(find.byKey(const Key('participant-save')));
    await tester.pumpAndSettle();

    final saved = (await SettingsStore().loadParticipants()).single;
    expect(saved.id, created.id);
    expect(saved.name, 'Orchid');
    expect(saved.systemPrompt, 'Respond in short paragraphs.');
    expect(saved.configuration.apiKey, 'atlas-test-key');

    await tester.tap(find.byTooltip('Model options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete model'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(controller.participants, isEmpty);
    expect(await SettingsStore().loadParticipants(), isEmpty);
  });

  test(
    'profile settings round trip independently of the main connection',
    () async {
      SharedPreferences.setMockInitialValues({
        'deepseek_chat:api-key': 'main-key',
      });
      final store = SettingsStore();
      await store.saveParticipants(const [
        ChatParticipant(
          id: 'first',
          name: 'First',
          configuration: ModelConfiguration(apiKey: 'first-key'),
          avatarBase64: 'YQ==',
        ),
        ChatParticipant(
          id: 'other',
          name: 'Other',
          configuration: ModelConfiguration(
            protocol: ApiProtocol.openaiCompatible,
            apiOrigin: 'https://other.example/v1',
            apiKey: 'other-key',
            model: 'other-chat',
            supportsAudio: true,
          ),
          systemPrompt: 'Custom prompt',
        ),
      ]);
      final loaded = await store.loadParticipants();
      expect(loaded.map((participant) => participant.id), ['first', 'other']);
      expect(loaded.first.avatarBase64, 'YQ==');
      expect(loaded.first.configuration.apiKey, 'first-key');
      expect(loaded.last.avatarBase64, isNull);
      expect(loaded.last.systemPrompt, 'Custom prompt');
      expect(loaded.last.configuration.supportsAudio, isTrue);
      expect(loaded.last.configuration.apiKey, 'other-key');
      expect((await store.load()).apiKey, 'main-key');
    },
  );
}
