import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/ui/home/hanging_wordmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('home layout and mode controls at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final controller = ChatController();
      await tester.pumpWidget(DeepSeekChatApp(controller: controller));
      await tester.pumpAndSettle();
      final mark = tester.getRect(find.byType(HangingWordmark));
      final chat = tester.getCenter(find.text('开始对话'));
      final persona = tester.getCenter(find.text('人格'));
      final settings = tester.getCenter(find.text('设置'));
      final footer = tester.getCenter(find.text('GitHub'));
      expect(mark.bottom, lessThan(chat.dy));
      expect(chat.dy, lessThan(persona.dy));
      expect(persona.dx, lessThan(settings.dx));
      expect(persona.dy, settings.dy);
      expect(footer.dy, inInclusiveRange(settings.dy + 1, size.height));
      expect(controller.settings.isAdvancedMode, isFalse);
      await tester.tap(find.text('进阶模式'));
      await tester.pumpAndSettle();
      expect(controller.settings.isAdvancedMode, isTrue);
      await tester.tap(find.text('普通模式'));
      await tester.pumpAndSettle();
      expect(controller.settings.isAdvancedMode, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all footer destinations open and return with reduced motion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await tester.pumpWidget(DeepSeekChatApp(controller: ChatController()));
    await tester.pumpAndSettle();
    for (final item in ['关于', '项目', '社区', 'GitHub']) {
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(item),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
  });
}
