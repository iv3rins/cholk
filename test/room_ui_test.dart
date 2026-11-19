import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_member.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/chat/chat_input.dart';
import 'package:deepseek_chat/ui/chat/recipient_picker.dart';
import 'package:deepseek_chat/ui/selection_feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A minimal host: no app shell, no settings pages, just the scope these
/// widgets read.
Widget _harness(ChatController controller, Widget child, {bool zh = true}) =>
    MaterialApp(
      theme: buildTheme(lightPalette),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => AppScope(
            controller: controller,
            strings: S(zh),
            palette: lightPalette,
            child: child,
          ),
        ),
      ),
    );

Future<ChatController> _controller({bool advanced = false}) async {
  SharedPreferences.setMockInitialValues({});
  final controller = ChatController();
  if (advanced) controller.settings.isAdvancedMode = true;
  return controller;
}

void main() {
  testWidgets('recipient sheet adds members with their own ids and one model', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller, const RecipientPicker(enabled: true)),
    );
    await tester.tap(find.byKey(const ValueKey('chat-recipients')));
    await tester.pumpAndSettle();

    Future<void> addMember(String name, String chipKey) async {
      await tester.tap(find.byKey(const Key('recipient-add-member')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipient-member-name')),
        name,
      );
      await tester.pump();
      final chip = find.byKey(ValueKey(chipKey));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      await tester.tap(find.byKey(const Key('recipient-member-confirm')));
      await tester.pumpAndSettle();
    }

    // One model, two members: each add creates its own identity.
    await addMember('小满', 'recipient-model-0');
    await addMember('阿澈', 'recipient-model-0');

    await tester.tap(find.byKey(const Key('recipient-done')));
    await tester.pumpAndSettle();

    final members = controller.chatMembers;
    expect(members.length, 2);
    expect(members.map((member) => member.name), ['小满', '阿澈']);
    // Both members are offered models, whichever the list resolves to.
    expect(members.every((member) => member.model.model.isNotEmpty), isTrue);
    expect(members[0].id, isNot(members[1].id));
    expect(controller.selectedChatMemberIds.length, 2);
    expect(controller.draftKey, '__new__');
  });

  testWidgets('adding a member does not offer a disconnected default model', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final previous = controller.availableChatModels.single;
    await controller.setChatModel(previous);
    await controller.setServerAddress('https://account.example');
    expect(controller.selectedChatModel, previous);
    expect(controller.availableChatModels, isEmpty);

    await tester.pumpWidget(
      _harness(controller, const RecipientPicker(enabled: true)),
    );
    await tester.tap(find.byKey(const ValueKey('chat-recipients')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recipient-add-member')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-model-0')), findsNothing);
  });

  testWidgets('removing a member before Done drops it from the room', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(controller, const RecipientPicker(enabled: true)),
    );
    await tester.tap(find.byKey(const ValueKey('chat-recipients')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recipient-add-member')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipient-member-name')), '小满');
    await tester.pump();
    await tester.tap(find.byKey(const Key('recipient-member-confirm')));
    await tester.pumpAndSettle();

    final remove = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          switch (widget.key) {
            ValueKey<String>(value: final key) => key.startsWith(
              'recipient-remove-',
            ),
            _ => false,
          },
    );
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(remove, findsNothing);

    await tester.tap(find.byKey(const Key('recipient-done')));
    await tester.pumpAndSettle();
    expect(controller.chatMembers, isEmpty);
  });

  testWidgets('assistant menu switches the default model and names it', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    controller.settings.apiKey = 'test-key';
    controller.settings.modelConfiguration = controller.settings
        .modelConfiguration
        .copyWith(model: 'deepseek-chat');

    await tester.pumpWidget(_harness(controller, const ChatInput()));
    await tester.tap(find.byKey(const Key('chat-assistant')));
    await tester.pumpAndSettle();

    final modelItems = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('chat-model-'),
    );
    expect(modelItems, findsWidgets);
    await tester.tap(modelItems.first);
    await tester.pumpAndSettle();

    final applied = controller.selectedChatModel;
    expect(applied, isNotNull);
    // The notice names the model that actually took effect.
    expect(find.text('默认助手：${applied!.model}'), findsOneWidget);
  });

  testWidgets('advanced mode offers editing the current persona', (
    tester,
  ) async {
    final controller = await _controller(advanced: true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller, const ChatInput()));
    await tester.tap(find.byKey(const Key('chat-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-persona-edit')), findsOneWidget);
  });

  testWidgets('normal mode has no persona editor entry', (tester) async {
    final controller = await _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_harness(controller, const ChatInput()));
    await tester.tap(find.byKey(const Key('chat-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-persona-edit')), findsNothing);
  });

  testWidgets('a centred notice names the value and clears itself', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final anchor = GlobalKey();

    await tester.pumpWidget(
      _harness(
        controller,
        Column(
          children: [const Spacer(), Container(key: anchor, height: 80)],
        ),
      ),
    );
    showCenteredNotice(
      anchor.currentContext!,
      CenteredNotice.label(dimension: 'Mode', value: 'Work', zh: false),
    );
    await tester.pump();
    expect(find.byKey(const Key('centered-notice')), findsOneWidget);
    expect(find.text('Mode: Work'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('centered-notice')), findsNothing);
    hideCenteredNotice();
  });

  test('room members keep a repeated model but not duplicate ids', () async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    const model = ChatModelRef('deepseek-chat');
    await controller.setRoomMembers(const [
      ChatMember('a', '小满', model),
      ChatMember('b', '阿澈', model),
    ], const ['b']);
    expect(controller.chatMembers.length, 2);
    expect(controller.selectedChatMemberIds, ['b']);

    // Dropping a member also drops its selection.
    await controller.setRoomMembers(const [
      ChatMember('a', '小满', model),
    ], const ['b']);
    expect(controller.selectedChatMemberIds, isEmpty);
    expect(controller.chatMembers.single.name, '小满');
  });
}
