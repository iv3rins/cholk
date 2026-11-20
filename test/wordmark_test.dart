import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/ui/home/hanging_wordmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester, {bool still = false}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (still) {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.pumpWidget(DeepSeekChatApp(controller: ChatController()));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a letter pulls its cord and the wordmark settles', (
    tester,
  ) async {
    await pumpHome(tester);
    final wordmark = find.byType(HangingWordmark);
    expect(wordmark, findsOneWidget);
    expect(find.bySemanticsLabel('CHOLK'), findsOneWidget);

    final rect = tester.getRect(wordmark);
    // The letter O sits near the middle of the bottom band.
    final letter = Offset(rect.center.dx, rect.top + rect.height * .78);
    final gesture = await tester.startGesture(letter);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(14, 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The ticker keeps running while the letter is held away from rest.
    expect(tester.binding.hasScheduledFrame, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only letters and cords take a drag', (tester) async {
    await pumpHome(tester);
    final rect = tester.getRect(find.byType(HangingWordmark));
    final canvas = tester.renderObject(find.byKey(const Key('wordmark-canvas')));
    bool hits(Offset point) => tester
        .hitTestOnBinding(point)
        .path
        .any((entry) => entry.target == canvas);
    // Empty stage space is left to the page scroll.
    expect(hits(rect.topLeft + const Offset(4, 30)), isFalse);
    expect(hits(Offset(rect.center.dx, rect.top + rect.height * .78)), isTrue);
  });

  testWidgets('reduced motion shows the wordmark still', (tester) async {
    await pumpHome(tester, still: true);
    final wordmark = find.byType(HangingWordmark);
    await tester.drag(wordmark, const Offset(40, 20), warnIfMissed: false);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byKey(const Key('wordmark-tilt')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
