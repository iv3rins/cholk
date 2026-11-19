import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/chat/attachments.dart';
import 'package:deepseek_chat/models/model_configuration.dart';

void main() {
  const deepseek = ModelConfiguration();
  const textOnly = ModelConfiguration(
    protocol: ApiProtocol.openaiCompatible,
    supportsImages: false,
    supportsPdf: false,
    supportsAudio: false,
  );

  test('DeepSeek retains document and image upload formats', () {
    expect(acceptedExtensionsFor(deepseek), acceptedExtensions);
    for (final name in [
      'report.docx',
      'slides.pptx',
      'book.epub',
      'icon.svg',
    ]) {
      expect(isAcceptedFile(name, configuration: deepseek), isTrue);
    }
    expect(isAcceptedFile('voice.mp3', configuration: deepseek), isFalse);
    expect(maxSizeMbFor('data.csv', false), 32);
    expect(maxSizeMbFor('report.pdf', false), 64);
  });

  test('compatible text input excludes binary document containers', () {
    for (final name in ['readme.MD', 'data.csv', 'main.dart', 'app.tsx']) {
      expect(isAcceptedFile(name, configuration: textOnly), isTrue);
      expect(attachmentSupportError(name, textOnly), isNull);
    }
    for (final name in [
      'report.docx',
      'report.doc',
      'slides.pptx',
      'table.xlsx',
      'book.epub',
      'archive.zip',
      'photo.heic',
      'icon.svg',
      'recording.m4a',
    ]) {
      expect(isAcceptedFile(name, configuration: textOnly), isFalse);
      expect(attachmentSupportError(name, textOnly), isNotNull);
    }
  });

  test('each media capability enables only its transport formats', () {
    final images = textOnly.copyWith(supportsImages: true);
    final pdf = textOnly.copyWith(supportsPdf: true);
    final audio = textOnly.copyWith(supportsAudio: true);
    expect(
      acceptedExtensionsFor(images),
      containsAll(['jpg', 'jpeg', 'png', 'gif', 'webp']),
    );
    expect(isAcceptedFile('page.pdf', configuration: images), isFalse);
    expect(isAcceptedFile('photo.svg', configuration: images), isFalse);
    expect(isAcceptedFile('page.PDF', configuration: pdf), isTrue);
    expect(isAcceptedFile('voice.wav', configuration: pdf), isFalse);
    expect(isAcceptedFile('voice.WAV', configuration: audio), isTrue);
    expect(isAcceptedFile('voice.mp3', configuration: audio), isTrue);
    expect(isAcceptedFile('voice.flac', configuration: audio), isFalse);
    expect(isAcceptedFile('photo.png', configuration: audio), isFalse);
  });

  test('disabled media explains the missing model capability', () {
    expect(attachmentSupportError('photo.png', textOnly), contains('图片'));
    expect(attachmentSupportError('page.pdf', textOnly), contains('PDF'));
    expect(attachmentSupportError('voice.mp3', textOnly), contains('音频'));
    expect(
      attachmentSupportError('voice.mp3', textOnly, isZh: false),
      contains('Audio input is disabled'),
    );
    expect(
      attachmentSupportError(
        'voice.mp3',
        textOnly.copyWith(supportsAudio: true),
      ),
      isNull,
    );
  });

  test('compatible limits apply to local text and enabled media', () {
    expect(maxSizeMbFor('main.dart', false, configuration: textOnly), 32);
    expect(maxSizeMbFor('voice.mp3', false, configuration: textOnly), 64);
    expect(maxSizeMbFor('photo.png', true, configuration: textOnly), 64);
  });
}
