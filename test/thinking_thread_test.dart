import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/chat/assistant_message.dart';

void main() {
  testWidgets(
    'thinking thread follows actual reasoning and respects reduced motion',
    (tester) async {
      final chat = ChatController();
      addTearDown(chat.dispose);
      final reply = AssistantMessage(
        id: 'a',
        createdAt: 1,
        status: ReplyStatus.streaming,
      );
      const threadKey = ValueKey('thinking-thread');
      final thread = find.byKey(threadKey);
      final thinking = find.text('深度思考中');

      Future<void> show({bool reduceMotion = false}) => tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(lightPalette),
          home: AppScope(
            controller: chat,
            strings: const S(true),
            palette: lightPalette,
            child: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: AssistantMessageTile(
                    message: reply,
                    streaming: reply.isStreaming,
                    versions: null,
                    onRegenerate: () {},
                    onContinue: () {},
                    onSwitchVersion: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await show();
      expect(find.bySemanticsLabel(const S(true).waiting), findsOneWidget);
      expect(thinking, findsNothing);
      expect(thread, findsNothing);

      final block = ThinkingBlock(thinking: '  ', startedAt: 1);
      reply.blocks.add(block);
      await show();
      expect(thread, findsNothing);
      block.thinking = 'Actual reasoning';
      await show();
      expect(thinking, findsOneWidget);
      expect(thread, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await show(reduceMotion: true);
      await tester.pumpAndSettle();
      expect(thread, findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      reply.blocks.add(TextBlock(text: 'Answer'));
      await show();
      expect(thinking, findsNothing);
      expect(thread, findsNothing);

      reply.blocks.add(
        ThinkingBlock(thinking: 'Second reasoning', startedAt: 10),
      );
      await show();
      expect(thinking, findsOneWidget);
      reply.blocks.add(
        ServerToolUseBlock(
          id: 'tool',
          name: 'web_search',
          kind: 'web_search',
          input: const {},
          raw: const {},
        ),
      );
      await show();
      expect(thinking, findsNothing);
      expect(thread, findsNothing);

      final closing = ThinkingBlock(thinking: 'Final reasoning', startedAt: 20);
      reply.blocks.add(closing);
      await show();
      expect(thread, findsOneWidget);
      closing.endedAt = 1500;
      await show();
      expect(thread, findsNothing);
      reply.blocks.add(ThinkingBlock(thinking: 'Still open on disconnect'));
      await show();
      expect(thread, findsOneWidget);
      reply.status = ReplyStatus.stopped;
      await show();
      expect(thinking, findsNothing);
      expect(thread, findsNothing);
      await tester.pumpAndSettle();
    },
  );
}
