import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/lineism.dart';
import '../common.dart';

class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.onCitation,
    this.onLink,
    this.selectable = true,
  });

  final String data;

  /// Inline selection; disabled on touch so the bubble's long-press menu wins.
  final bool selectable;
  final void Function(int index)? onCitation;
  final void Function(String url)? onLink;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  String? _cachedData;
  bool? _cachedDark;
  double? _cachedScale;
  bool? _cachedSelectable;
  Widget? _cached;

  String _withCitationLinks(String source) {
    return source.replaceAllMapped(
      RegExp(r'\[citation:(\d+)\]'),
      (match) => '[[${match.group(1)}]](citation:${match.group(1)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.of(context).palette;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (_cached != null &&
        _cachedData == widget.data &&
        _cachedDark == palette.isDark &&
        _cachedScale == scale &&
        _cachedSelectable == widget.selectable) {
      return _cached!;
    }
    _cachedSelectable = widget.selectable;
    _cachedData = widget.data;
    _cachedDark = palette.isDark;
    _cachedScale = scale;

    final base = Lineism.serif.copyWith(
      color: palette.textPrimary,
      fontSize: 16,
      height: 1.75,
    );

    final styleSheet = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 10),
      a: base.copyWith(
        color: palette.lineInk,
        decoration: TextDecoration.underline,
        decorationColor: palette.lineInk,
      ),
      em: base.copyWith(fontStyle: FontStyle.italic),
      strong: base.copyWith(fontWeight: FontWeight.w600),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      h1: base.copyWith(
        fontSize: 24,
        height: 1.42,
        fontWeight: FontWeight.w700,
      ),
      h1Padding: const EdgeInsets.only(top: 10, bottom: 8),
      h2: base.copyWith(
        fontSize: 22,
        height: 1.45,
        fontWeight: FontWeight.w700,
      ),
      h2Padding: const EdgeInsets.only(top: 8, bottom: 6),
      h3: base.copyWith(fontSize: 20, height: 1.5, fontWeight: FontWeight.w700),
      h3Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h4: base.copyWith(
        fontSize: 16,
        height: 1.75,
        fontWeight: FontWeight.w600,
      ),
      h4Padding: const EdgeInsets.only(top: 4, bottom: 2),
      code: Lineism.serif.copyWith(
        fontSize: 13.5,
        color: palette.textPrimary,
        backgroundColor: palette.inlineCode,
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: BoxDecoration(
        color: palette.codeBackground,
        border: Border.all(color: palette.lineRule, width: Lineism.base),
      ),
      blockquote: base.copyWith(color: palette.textSecondary),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.lineRule, width: 2)),
      ),
      listBullet: base,
      listIndent: 22,
      tableHead: base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.6,
      ),
      tableBody: base.copyWith(fontSize: 15, height: 1.6),
      tableBorder: TableBorder.all(
        color: palette.lineRule,
        width: Lineism.hair,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      blockSpacing: 10,
    );

    final highlightTheme = _lineismHighlightTheme(palette);

    _cached = MarkdownBody(
      data: _withCitationLinks(widget.data),
      selectable: widget.selectable,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {
        'pre': _CodeBlockBuilder(palette: palette, theme: highlightTheme),
      },
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        if (href.startsWith('citation:')) {
          final index = int.tryParse(href.substring('citation:'.length));
          if (index != null) widget.onCitation?.call(index);
          return;
        }
        if (widget.onLink != null) {
          widget.onLink!(href);
        } else {
          openExternalUrl(href);
        }
      },
    );
    return _cached!;
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.palette, required this.theme});

  final AppPalette palette;
  final Map<String, TextStyle> theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String language = '';
    String code = element.textContent;
    final children = element.children;
    if (children != null && children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element) {
        final className = first.attributes['class'];
        if (className != null && className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
      }
    }
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }
    return CodeBlock(
      code: code,
      language: language,
      palette: palette,
      theme: theme,
    );
  }
}

class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.palette,
    required this.theme,
  });

  final String code;
  final String language;
  final AppPalette palette;
  final Map<String, TextStyle> theme;

  @override
  Widget build(BuildContext context) {
    final lang = language.toLowerCase();
    final known = _knownLanguages.contains(lang) ? lang : null;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      decoration: BoxDecoration(
        color: palette.codeBackground,
        border: Border.all(color: palette.lineRule, width: Lineism.base),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.codeBanner,
              border: Border(
                bottom: BorderSide(
                  color: palette.lineRule,
                  width: Lineism.hair,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 12, right: 4),
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      color: palette.textTertiary,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: AppScope.of(context).strings.copy,
                  size: 26,
                  iconSize: 14,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showToast(context, AppScope.of(context).strings.copied);
                  },
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              code,
              language: known,
              theme: theme,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              textStyle: Lineism.serif.copyWith(fontSize: 13, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

const Set<String> _knownLanguages = {
  'bash',
  'c',
  'cpp',
  'csharp',
  'css',
  'dart',
  'diff',
  'go',
  'graphql',
  'ini',
  'java',
  'javascript',
  'json',
  'kotlin',
  'less',
  'lua',
  'makefile',
  'markdown',
  'objectivec',
  'perl',
  'php',
  'plaintext',
  'python',
  'r',
  'ruby',
  'rust',
  'scss',
  'shell',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
};

Map<String, TextStyle> _lineismHighlightTheme(AppPalette palette) {
  final base = TextStyle(color: palette.lineInk);
  return {
    'root': base.copyWith(backgroundColor: Colors.transparent),
    'keyword': base.copyWith(fontWeight: FontWeight.w600),
    'built_in': base.copyWith(color: palette.lineInk2),
    'string': base.copyWith(color: palette.lineInk2),
    'comment': base.copyWith(
      color: palette.lineRule,
      fontStyle: FontStyle.italic,
    ),
    'number': base.copyWith(color: palette.lineInk2),
    'title': base.copyWith(fontWeight: FontWeight.w600),
    'attr': base.copyWith(color: palette.lineInk2),
    'literal': base.copyWith(color: palette.lineInk2),
    'meta': base.copyWith(color: palette.lineInk2),
    'selector-tag': base.copyWith(fontWeight: FontWeight.w600),
    'selector-class': base.copyWith(color: palette.lineInk2),
    'selector-id': base.copyWith(color: palette.lineInk2),
    'tag': base.copyWith(fontWeight: FontWeight.w600),
    'name': base.copyWith(color: palette.lineInk2),
    'type': base.copyWith(color: palette.lineInk2),
    'symbol': base.copyWith(color: palette.lineInk2),
    'bullet': base.copyWith(color: palette.lineInk2),
    'emphasis': base.copyWith(fontStyle: FontStyle.italic),
    'strong': base.copyWith(fontWeight: FontWeight.w600),
    'link': base.copyWith(decoration: TextDecoration.underline),
  };
}
