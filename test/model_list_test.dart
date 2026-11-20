import 'package:deepseek_chat/api/api_client.dart';
import 'package:deepseek_chat/ui/app_scope.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/model_configuration.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/settings/model_configuration_fields.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dio _fakeDio(List<Uri> requests, List<String?> auth, Object body) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri);
            auth.add(options.headers['Authorization'] as String?);
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: body),
            );
          },
        ),
      );

Future<void> _pumpFields(
  WidgetTester tester,
  ChatController controller,
  ModelConfiguration configuration,
) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(lightPalette),
    builder: (context, child) => AppScope(
      controller: controller,
      strings: const S(false),
      palette: lightPalette,
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ModelConfigurationFields(initialConfiguration: configuration),
      ),
    ),
  ),
);

String _modelText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('api-model')),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

void main() {
  test('parseModelIds keeps string ids, dedups and sorts', () {
    expect(
      parseModelIds({
        'object': 'list',
        'data': [
          {'id': 'gpt-b'},
          {'id': 'deepseek-chat'},
          {'id': 'gpt-b'},
          {'id': 3},
          {'name': 'no-id'},
          'junk',
          {'id': '  '},
          {'id': 'deepseek-reasoner'},
        ],
      }),
      ['deepseek-chat', 'deepseek-reasoner', 'gpt-b'],
    );
    expect(parseModelIds({'data': 'x'}), isEmpty);
    expect(parseModelIds(null), isEmpty);
  });

  test('listModels calls GET {origin}/models with a bearer key', () async {
    final requests = <Uri>[];
    final auth = <String?>[];
    final client = ApiClient(
      dio: _fakeDio(requests, auth, {
        'data': [
          {'id': 'b'},
          {'id': 'a'},
        ],
      }),
    );
    final models = await client
        .forOrigin('https://example.com/v1')
        .listModels('sk-test');
    expect(models, ['a', 'b']);
    expect(requests.single.toString(), 'https://example.com/v1/models');
    expect(auth.single, 'Bearer sk-test');
  });

  testWidgets('fetch button picks a model into the model field', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final controller = ChatController(
      apiClient: ApiClient(
        dio: _fakeDio(requests, [], {
          'data': [
            {'id': 'deepseek-reasoner'},
            {'id': 'deepseek-chat'},
          ],
        }),
      ),
    );
    addTearDown(controller.dispose);
    await _pumpFields(
      tester,
      controller,
      const ModelConfiguration(apiKey: 'sk-test', model: ''),
    );

    final button = find.byKey(const Key('api-fetch-models'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(requests.single.toString(), 'https://api.deepseek.com/models');

    await tester.enterText(find.byKey(const Key('api-models-filter')), 'reas');
    await tester.pumpAndSettle();
    expect(find.text('deepseek-chat'), findsNothing);
    await tester.tap(find.text('deepseek-reasoner'));
    await tester.pumpAndSettle();
    expect(_modelText(tester), 'deepseek-reasoner');
  });

  testWidgets('fetch without a key shows a message and sends nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final controller = ChatController(
      apiClient: ApiClient(dio: _fakeDio(requests, [], {'data': []})),
    );
    addTearDown(controller.dispose);
    await _pumpFields(tester, controller, const ModelConfiguration());

    await tester.tap(find.byKey(const Key('api-fetch-models')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text(const S(false).apiKeyRequired), findsWidgets);
  });
}
