import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../i18n/strings_messages.dart';
import '../app_scope.dart';
import '../common.dart';

/// Whether the current platform is a touch platform (Android / iOS).
bool isTouchPlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

/// Copies [text] to the clipboard and shows the "Copied" toast.
void copyMessageText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(context, AppScope.of(context).strings.copied);
}

/// Long-press menu for a message: Copy / Select text.
Future<void> showMessageActions(BuildContext context, String text) {
  if (text.isEmpty) return Future.value();
  HapticFeedback.selectionClick();
  final strings = AppScope.of(context).strings;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(strings.copy),
            onTap: () {
              Navigator.of(sheetContext).pop();
              copyMessageText(context, text);
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(strings.selectText),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SelectMessageTextPage(text: text),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Full-screen page showing the message as selectable text with native handles.
class SelectMessageTextPage extends StatelessWidget {
  const SelectMessageTextPage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final strings = scope.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.selectText),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: strings.copy,
            onPressed: () => copyMessageText(context, text),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: scope.palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
