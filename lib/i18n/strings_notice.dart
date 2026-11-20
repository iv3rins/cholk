import 'strings.dart';

extension NoticeStrings on S {
  String get disclaimerTitle => isZh ? '免责声明' : 'Disclaimer';
  String get disclaimerAccept => isZh ? '我已了解' : 'I understand';

  List<String> get disclaimerParagraphs => isZh
      ? const [
          'Cholk 只是一个客户端，用来连接你自己配置的模型接口。你对输入的内容、得到的回复以及如何使用它们负责。',
          '请遵守各模型服务商的使用政策。Cholk 不支持、也不协助越狱、“破甲”或任何绕过模型安全措施的做法。',
          '因滥用造成的后果由使用者自行承担，作者不承担责任。本软件以 MIT 许可证“按原样”提供，不附带任何担保。',
        ]
      : const [
          'Cholk is only a client for the model APIs you configure. You are responsible for what you send, the replies you get, and how you use them.',
          'Follow the usage policies of each model provider. Cholk does not support or assist jailbreaking or any attempt to bypass a model\'s safety measures.',
          'The author is not responsible for consequences of misuse. The software is provided "as is" under the MIT license, without warranty.',
        ];
}
