import 'package:deepseek_chat/chat/group_history.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

UserMessage _user(String id, String content) =>
    UserMessage(id: id, createdAt: 0, content: content);

AssistantMessage _reply(String id, String? participantId, String name, String text) =>
    AssistantMessage(
      id: id,
      createdAt: 0,
      participantId: participantId,
      participantName: name,
      status: ReplyStatus.done,
      blocks: [TextBlock(text: text)],
    );

void main() {
  final history = <ChatMessage>[
    _user('u1', 'Hi all'),
    _reply('a1', 'a', '小艾', 'Hello from A'),
    _reply('b1', 'b', '小贝', '[小贝]\nHello from B'),
    _user('u2', 'Only A'),
    _reply('a2', 'a', '小艾', 'A again'),
  ];

  test('own replies stay assistant; other members arrive as attributed user text', () {
    final view = groupHistoryFor(history, participantId: 'b', zh: true);
    expect(view.history, hasLength(2));
    final user = view.history[0] as UserMessage;
    final own = view.history[1] as AssistantMessage;
    expect(user.content, 'Hi all');
    expect(own.text, 'Hello from B', reason: 'own label is stripped');
    expect(
      view.pending,
      '「小艾」说：Hello from A\n\n用户说：Only A\n\n「小艾」说：A again',
    );
    final question = withGroupContext(_user('u3', 'Next'), view.pending);
    expect(question.content, '${view.pending}\n\nNext');
    expect(question.id, 'u3');
  });

  test('other members of earlier turns lead the next own user turn', () {
    final view = groupHistoryFor(history, participantId: 'a', zh: false);
    expect([for (final m in view.history) m.role], [
      'user',
      'assistant',
      'user',
      'assistant',
    ]);
    expect((view.history[2] as UserMessage).content, '小贝 said: Hello from B\n\nOnly A');
    expect((view.history[3] as AssistantMessage).text, 'A again');
    expect(view.pending, isEmpty);
    final question = _user('u3', 'Next');
    expect(identical(withGroupContext(question, view.pending), question), isTrue);
    for (final message in view.history.whereType<AssistantMessage>()) {
      expect(message.text, isNot(contains('[')));
    }
  });

  test('strips only a leading name tag', () {
    for (final tagged in [
      '[小艾] 你好',
      '[小艾]\n你好',
      '【小艾】你好',
      '「小艾」 你好',
      '小艾：你好',
      '  小艾: 你好',
    ]) {
      expect(stripLeadingNameTag(tagged, '小艾'), '你好', reason: tagged);
    }
    expect(stripLeadingNameTag('你好，小艾：在吗', '小艾'), '你好，小艾：在吗');
    expect(stripLeadingNameTag('[小贝] 你好', '小艾'), '[小贝] 你好');
    expect(stripLeadingNameTag('小艾说得对', '小艾'), '小艾说得对');
  });
}
