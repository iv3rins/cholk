// Transitive dependencies of `file_picker`: this fake needs their types.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:deepseek_chat/app.dart';
import 'package:deepseek_chat/i18n/strings.dart';
import 'package:deepseek_chat/models/persona.dart';
import 'package:deepseek_chat/state/chat_controller.dart';
import 'package:deepseek_chat/theme/app_theme.dart';
import 'package:deepseek_chat/ui/persona/persona_editor_page.dart';
import 'package:deepseek_chat/ui/persona/persona_page.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `PlatformFile` is an abstract base class, so tests supply their own
/// in-memory implementation instead of a constructor.
final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.name, this._bytes);

  @override
  final String name;

  final Uint8List _bytes;

  @override
  Uri get uri => Uri.parse('memory:///$name');

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

class _FakeFilePicker extends FilePickerPlatform {
  List<PlatformFile> files = const [];
  Object? error;
  int saves = 0;
  final List<String> fileNames = [];
  final Map<String, Uint8List> saved = {};
  bool cancelSave = false;

  Uint8List bytesFor(String fileName) => saved[fileName]!;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (error != null) throw error!;
    return files;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saves++;
    fileNames.add(fileName);
    if (error != null) throw error!;
    if (cancelSave) return null;
    saved[fileName] = bytes;
    return Uri(path: fileName);
  }
}

Widget _app(ChatController controller, Widget home, {bool zh = true}) =>
    MaterialApp(
      theme: buildTheme(lightPalette),
      builder: (context, child) => AppScope(
        controller: controller,
        strings: S(zh),
        palette: lightPalette,
        child: child!,
      ),
      home: home,
    );

void main() {
  test(
    'every built-in persona exports and imports as v1 in both languages',
    () {
      for (final original in personas) {
        for (final zh in [true, false]) {
          final restored = Persona.importJson(
            original.exportJson(zh: zh),
            id: 'restored-${original.id}',
          );
          expect(restored.name(zh), original.name(zh));
          expect(restored.prompt(zh) ?? '', original.prompt(zh) ?? '');
          expect(restored.workflow, original.workflow);
          expect(restored.isCustom, isTrue);
        }
      }
    },
  );

  test('v1 import accepts omitted workflow and an empty system prompt', () {
    final restored = Persona.importJson(
      '{"version":1,"name":"Default copy","system_prompt":""}',
      id: 'copy',
    );
    expect(restored.prompt(true), isEmpty);
    expect(restored.workflow, isEmpty);
  });

  testWidgets('built-in editor saves a copy with English initial values', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatController();
    addTearDown(controller.dispose);
    final original = personaById('engineer');
    Persona? result;
    await tester.pumpWidget(
      _app(
        controller,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await openPersonaEditor(context, persona: original);
            },
            child: const Text('Open'),
          ),
        ),
        zh: false,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rigorous engineer'), findsOneWidget);
    expect(find.text(original.promptEn!), findsOneWidget);
    expect(find.textContaining('built-in'), findsOneWidget);
    await tester.tap(find.byKey(const Key('persona-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.id, isNot(original.id));
    expect(result!.name(false), original.nameEn);
    expect(result!.prompt(false), original.promptEn);
    expect(controller.personaForId(original.id).promptEn, original.promptEn);
    expect(controller.personaForId(result!.id), same(result));
  });

  group('persona JSON file feedback', () {
    late FilePickerPlatform previous;
    late _FakeFilePicker picker;
    late ChatController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      previous = FilePickerPlatform.instance;
      picker = _FakeFilePicker();
      FilePickerPlatform.instance = picker;
      controller = ChatController();
    });

    tearDown(() {
      FilePickerPlatform.instance = previous;
      controller.dispose();
    });

    testWidgets('import shows success only after storing the persona', (
      tester,
    ) async {
      final bytes = utf8.encode(
        '{"version":1,"name":"Imported","system_prompt":"Hello"}',
      );
      picker.files = [_MemoryFile('persona.json', bytes)];
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      await tester.tap(find.byKey(const Key('import-persona')));
      await tester.pumpAndSettle();
      expect(find.textContaining('人格导入成功'), findsOneWidget);
      expect(controller.personaOptions.last.name(true), 'Imported');
    });

    testWidgets('invalid import shows failure', (tester) async {
      final bytes = utf8.encode('{"version":2}');
      picker.files = [_MemoryFile('bad.json', bytes)];
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      await tester.tap(find.byKey(const Key('import-persona')));
      await tester.pumpAndSettle();
      expect(find.textContaining('导入失败'), findsOneWidget);
    });

    testWidgets('export reports success after the native picker saves', (
      tester,
    ) async {
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      final options = find.byKey(const Key('persona-options-default'));
      await tester.tap(options);
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();
      // The default assistant has no prompt, and the default persona writes
      // "default" as its file name.
      expect(picker.saves, 1);
      expect(picker.fileNames, ['default.json']);
      expect(find.textContaining('人格导出成功'), findsOneWidget);
    });

    testWidgets('a prompt-less persona exports an empty prompt and reimports', (
      tester,
    ) async {
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      await tester.tap(find.byKey(const Key('persona-options-default')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();

      final exported = utf8.decode(picker.bytesFor('default.json'));
      expect(jsonDecode(exported), {
        'version': 1,
        'name': '默认助手',
        'system_prompt': '',
      });

      picker.files = [_MemoryFile('default.json', utf8.encode(exported))];
      await tester.tap(find.byKey(const Key('import-persona')));
      await tester.pumpAndSettle();
      final imported = controller.personaOptions.last;
      expect(imported.isCustom, isTrue);
      expect(imported.name(true), '默认助手');
      expect(imported.prompt(true), isEmpty);
      expect(imported.workflow, isEmpty);
    });

    testWidgets('cancelling native export does not report success', (
      tester,
    ) async {
      picker.cancelSave = true;
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      await tester.tap(find.byKey(const Key('persona-options-default')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();
      expect(picker.saves, 1);
      expect(picker.saved, isEmpty);
      expect(find.textContaining('人格导出成功'), findsNothing);
    });

    testWidgets('export exception shows failure', (tester) async {
      picker.error = StateError('save failed');
      await tester.pumpWidget(_app(controller, const PersonaPage()));
      await tester.tap(find.byKey(const Key('persona-options-default')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();
      expect(find.text('无法导出人格。'), findsOneWidget);
    });
  });
}
