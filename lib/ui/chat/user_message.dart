import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';
import '../common.dart';
import '../../theme/lineism.dart';
import '../participants/participant_avatar.dart';
import 'group_message.dart';
import 'local_image.dart';

class UserMessageTile extends StatefulWidget {
  const UserMessageTile({
    super.key,
    required this.message,
    required this.versions,
    required this.onEdit,
    required this.onSwitchVersion,
    this.streaming = false,
    this.groupChat = false,
  });

  final UserMessage message;
  final MessageVersions? versions;
  final void Function(String text) onEdit;
  final void Function(String messageId) onSwitchVersion;
  final bool streaming;
  final bool groupChat;

  @override
  State<UserMessageTile> createState() => _UserMessageTileState();
}

class _UserMessageTileState extends State<UserMessageTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final palette = scope.palette;
    final strings = scope.strings;
    final message = widget.message;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final isTouch =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final attachments = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final file in message.files)
          _AttachmentPreview(file: file, palette: palette),
      ],
    );
    final text = SelectableText(
      message.content,
      style: TextStyle(fontSize: 16, height: 1.5, color: palette.textPrimary),
    );
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.groupChat) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              strings.you,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          GroupBubble(
            outgoing: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.files.isNotEmpty) attachments,
                if (message.files.isNotEmpty && message.content.isNotEmpty)
                  const SizedBox(height: 8),
                if (message.content.isNotEmpty) text,
              ],
            ),
          ),
        ] else ...[
          if (message.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: attachments,
            ),
          if (message.content.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(right: 3, bottom: 3),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    palette.accentWash,
                    palette.background,
                  ),
                  border: Border.all(
                    color: palette.lineInk,
                    width: Lineism.base,
                  ),
                  boxShadow: [
                    BoxShadow(color: palette.accent, offset: Lineism.misprint),
                  ],
                ),
                child: text,
              ),
            ),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AnimatedOpacity(
              opacity: _hovering || isTouch ? 1 : .65,
              duration: Duration(
                milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 150,
              ),
              child: Wrap(
                children: [
                  if (message.content.isNotEmpty)
                    AppIconButton(
                      icon: Icons.copy_rounded,
                      tooltip: strings.copy,
                      size: 44,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: message.content));
                        showToast(context, strings.copied);
                      },
                    ),
                  if (!widget.streaming)
                    AppIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: strings.edit,
                      size: 44,
                      onPressed: () => _showEditor(context),
                    ),
                ],
              ),
            ),
            if (!widget.streaming &&
                widget.versions != null &&
                widget.versions!.ids.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: VersionSwitcher(
                  index: widget.versions!.index,
                  count: widget.versions!.ids.length,
                  onPrevious: () => widget.onSwitchVersion(
                    widget.versions!.ids[widget.versions!.index - 1],
                  ),
                  onNext: () => widget.onSwitchVersion(
                    widget.versions!.ids[widget.versions!.index + 1],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: widget.groupChat
            ? GroupMessage(
                outgoing: true,
                avatar: ParticipantAvatar(name: strings.you),
                child: row,
              )
            : row,
      ),
    );
  }

  Future<void> _showEditor(BuildContext context) async {
    final strings = AppScope.of(context).strings;
    final controller = TextEditingController(text: widget.message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.editPromptTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.editPromptHint,
                style: TextStyle(
                  fontSize: 13,
                  color: AppScope.of(context).palette.textTertiary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 8,
                decoration: InputDecoration(hintText: strings.inputPlaceholder),
              ),
              if (widget.message.files.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  strings.attachedFiles,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppScope.of(context).palette.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final file in widget.message.files)
                      Chip(
                        label: Text(
                          file.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.trim() != widget.message.content.trim()) {
      widget.onEdit(result);
    }
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.file, required this.palette});

  final FileAttachment file;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    final isFailed = file.status == AttachmentStatus.failed;
    final isUploading = file.status == AttachmentStatus.uploading;
    const radius = BorderRadius.zero;

    Widget content;
    if (file.isImage) {
      content = LocalAttachmentImage(file: file, size: 64, radius: 0);
    } else {
      content = Container(
        constraints: const BoxConstraints(maxWidth: 220),
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: radius,
          border: Border.all(
            color: isFailed ? palette.lineSignal : palette.lineRule,
            width: Lineism.hair,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              file.mimeType.toLowerCase().startsWith('audio/')
                  ? Icons.audio_file_outlined
                  : Icons.description_outlined,
              size: 22,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: palette.textPrimary),
                  ),
                  Text(
                    _formatSize(file.size),
                    style: TextStyle(fontSize: 10, color: palette.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: radius,
          child: Container(
            decoration: isFailed
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: palette.error, width: 1.5),
                  )
                : null,
            child: content,
          ),
        ),
        if (isUploading)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        if (isFailed)
          Positioned.fill(
            child: Tooltip(
              message: file.error ?? 'Upload failed',
              child: ClipRRect(
                borderRadius: radius,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.42),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
