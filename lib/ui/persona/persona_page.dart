import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/persona.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';
import '../participants/participant_profiles.dart';
import 'persona_editor_page.dart';

class PersonaPage extends StatefulWidget {
  const PersonaPage({super.key});

  @override
  State<PersonaPage> createState() => _PersonaPageState();
}

class _PersonaPageState extends State<PersonaPage> {
  bool _busy = false;

  Future<void> _import() async {
    if (_busy) return;
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (!mounted || files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final imported = await scope.controller.importPersona(utf8.decode(bytes));
      if (!mounted) return;
      showToast(
        context,
        scope.strings.isZh
            ? '人格导入成功：${imported.name(true)}'
            : 'Persona imported: ${imported.name(false)}',
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          scope.strings.isZh
              ? '导入失败，请选择有效的 Cholk 人格 JSON。'
              : 'Could not import. Choose a valid Cholk persona JSON.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(Persona persona) async {
    if (_busy) return;
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final json = persona.exportJson(zh: scope.strings.isZh);
      // The default Web picker starts a download and returns null. Native
      // pickers return null only when the user cancels.
      final destination = await FilePicker.saveFile(
        fileName: '${persona.id}.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (!mounted || (!kIsWeb && destination == null)) return;
      showToast(
        context,
        scope.strings.isZh
            ? '人格导出成功：${persona.name(true)}'
            : 'Persona exported: ${persona.name(false)}',
      );
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          scope.strings.isZh ? '无法导出人格。' : 'Could not export persona.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.controller;
    final palette = scope.palette;
    final strings = scope.strings;
    final zh = strings.isZh;
    final selectedId = controller.settings.personaId;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (palette.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: palette.background,
              ),
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(title: Text(strings.persona)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          children: [
            if (controller.settings.isAdvancedMode) ...[
              const ParticipantProfiles(),
              const SizedBox(height: 22),
              Container(height: Lineism.hair, color: palette.lineRule),
              const SizedBox(height: 18),
              Text(
                zh ? '默认连接人格' : 'Default connection persona',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              strings.personaPageDescription,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: palette.lineInk2,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('add-persona'),
                  onPressed: _busy ? null : () => openPersonaEditor(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(zh ? '新建人格' : 'New persona'),
                ),
                OutlinedButton.icon(
                  key: const Key('import-persona'),
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: Text(zh ? '导入 JSON' : 'Import JSON'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final persona in controller.personaOptions) ...[
              _PersonaRow(
                persona: persona,
                selected: persona.id == selectedId,
                zh: zh,
                busy: _busy,
                onTap: () => controller.setPersona(persona.id),
                onEdit: () => openPersonaEditor(context, persona: persona),
                onExport: () => _export(persona),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            Container(height: Lineism.hair, color: palette.lineRule),
            const SizedBox(height: 14),
            Text(
              zh ? 'Workflow 一行一步，仅进阶模式可编辑。保存后，普通与进阶模式都会作为提示词发送，不会在本地自动执行。' : 'Workflow uses one step per line and is editable in advanced mode only. Both modes send saved steps as prompts; nothing runs locally.',
              style: TextStyle(
                fontSize: 12,
                height: 1.65,
                color: palette.lineInk2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              strings.personaNote,
              style: TextStyle(
                fontSize: 12,
                height: 1.65,
                color: palette.lineInk2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaRow extends StatelessWidget {
  const _PersonaRow({
    required this.persona,
    required this.selected,
    required this.zh,
    required this.busy,
    required this.onTap,
    required this.onEdit,
    required this.onExport,
  });

  final Persona persona;
  final bool selected;
  final bool zh;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? palette.lineInk : palette.lineRule,
            width: selected ? Lineism.emphasis : Lineism.base,
          ),
        ),
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona.name(zh),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        persona.description(zh),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: palette.lineInk2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check_rounded, color: palette.lineInk, size: 20),
                ],
                PopupMenuButton<String>(
                  key: ValueKey('persona-options-${persona.id}'),
                  tooltip: zh ? '人格选项' : 'Persona options',
                  enabled: !busy,
                  borderRadius: BorderRadius.zero,
                  onSelected: (action) =>
                      action == 'edit' ? onEdit() : onExport(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(zh ? '编辑' : 'Edit'),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Text(zh ? '导出 JSON' : 'Export JSON'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
