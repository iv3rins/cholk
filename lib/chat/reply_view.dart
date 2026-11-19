import '../models/chat_models.dart';

enum ToolStatus { wip, done, failed }

class ReplySource {
  ReplySource({
    required this.url,
    required this.title,
    required this.siteName,
    this.publishedAt,
    this.snippet,
    this.siteIcon,
    required this.index,
  });

  final String url;
  String title;
  String siteName;
  String? publishedAt;
  String? snippet;
  String? siteIcon;
  final int index;
}

class SourceRegistry {
  final List<ReplySource> list = [];
  final Map<String, ReplySource> _byUrl = {};

  ReplySource add(
    String url,
    String? title, {
    String? publishedAt,
    String? snippet,
    String? siteIcon,
    String? siteName,
  }) {
    final existing = _byUrl[url];
    if (existing != null) {
      if (existing.title == url && title != null && title.isNotEmpty) {
        existing.title = title;
      }
      existing.publishedAt ??= publishedAt;
      existing.snippet ??= snippet;
      existing.siteIcon ??= siteIcon;
      return existing;
    }
    final source = ReplySource(
      url: url,
      title: (title == null || title.isEmpty) ? url : title,
      siteName: (siteName == null || siteName.trim().isEmpty)
          ? _siteName(url)
          : siteName.trim(),
      publishedAt: publishedAt,
      snippet: snippet,
      siteIcon: siteIcon,
      index: list.length + 1,
    );
    list.add(source);
    _byUrl[url] = source;
    return source;
  }

  ReplySource? byUrl(String url) => _byUrl[url];

  static String _siteName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host.replaceFirst(RegExp(r'^www\.'), '');
  }
}

sealed class ReplyStep {
  const ReplyStep();
}

class ThinkingStep extends ReplyStep {
  ThinkingStep(this.key, this.blocks);
  final String key;
  final List<ThinkingBlock> blocks;

  int? get seconds {
    var total = 0;
    for (final block in blocks) {
      if (block.elapsedSeconds != null) {
        total += block.elapsedSeconds! * 1000;
        continue;
      }
      if (block.startedAt == null) return null;
      total +=
          (block.endedAt ?? DateTime.now().millisecondsSinceEpoch) -
          block.startedAt!;
    }
    final result = (total / 1000).round();
    return result < 1 ? 1 : result;
  }
}

class SearchStep extends ReplyStep {
  SearchStep({
    required this.key,
    required this.kind,
    required this.queries,
    required this.results,
    required this.status,
  });
  final String key;
  final String kind;
  final List<String> queries;
  final List<ReplySource> results;
  ToolStatus status;
}

class ReadLinkStep extends ReplyStep {
  ReadLinkStep(this.links);
  final List<PageItem> links;
}

class OpenPageStep extends ReplyStep {
  OpenPageStep(this.pages);
  final List<PageItem> pages;
}

class FindInPageStep extends ReplyStep {
  FindInPageStep(this.patterns);
  final List<PatternItem> patterns;
}

class PageItem {
  PageItem({
    required this.id,
    required this.url,
    required this.title,
    required this.status,
  });
  final String id;
  final String url;
  final String title;
  ToolStatus status;
}

class PatternItem {
  PatternItem({required this.id, required this.pattern, required this.status});
  final String id;
  final String pattern;
  ToolStatus status;
}

class TextStep extends ReplyStep {
  TextStep(this.key, this.markdown);
  final String key;
  final String markdown;
}

class ReplyView {
  ReplyView({
    required this.steps,
    required this.answerMarkdown,
    required this.answerText,
    required this.sources,
    required this.searchResults,
  });

  final List<ReplyStep> steps;
  final String? answerMarkdown;
  final String answerText;
  final List<ReplySource> sources;
  final List<ReplySource> searchResults;

  bool get hasAnswer => answerMarkdown != null && answerText.trim().isNotEmpty;

  int? get thinkingSeconds {
    var total = 0;
    var found = false;
    for (final step in steps) {
      if (step is ThinkingStep) {
        found = true;
        final seconds = step.seconds;
        if (seconds == null) return null;
        total += seconds;
      }
    }
    if (!found) return null;
    return total < 1 ? 1 : total;
  }

  SearchStep? get lastSearch {
    for (var i = steps.length - 1; i >= 0; i--) {
      if (steps[i] is SearchStep) return steps[i] as SearchStep;
    }
    return null;
  }

  ReadLinkStep? get lastReadLink {
    for (var i = steps.length - 1; i >= 0; i--) {
      if (steps[i] is ReadLinkStep) return steps[i] as ReadLinkStep;
    }
    return null;
  }
}

bool _isDeepSearch(String kind) =>
    kind == 'deep_search' || kind == 'deep_image_search';

bool _isImageSearch(String kind) =>
    kind == 'image_search' || kind == 'deep_image_search';

ToolStatus _statusOf(
  WebSearchResultBlock? search,
  WebFetchResultBlock? fetch,
  bool streaming,
) {
  if (search != null) {
    return search.failed ? ToolStatus.failed : ToolStatus.done;
  }
  if (fetch != null) {
    return fetch.failed ? ToolStatus.failed : ToolStatus.done;
  }
  return streaming ? ToolStatus.wip : ToolStatus.failed;
}

ToolStatus _mergeStatus(Iterable<ToolStatus> statuses) {
  if (statuses.contains(ToolStatus.wip)) return ToolStatus.wip;
  if (statuses.every((status) => status == ToolStatus.failed)) {
    return ToolStatus.failed;
  }
  return ToolStatus.done;
}

({String markdown, String text}) _joinText(
  List<({String text, List<Citation> citations})> blocks,
  SourceRegistry registry,
) {
  var markdown = '';
  var text = '';
  for (final block in blocks) {
    text += block.text;
    final indexes = <int>{};
    for (final citation in block.citations) {
      indexes.add(registry.add(citation.url, citation.title).index);
    }
    final body = indexes.isNotEmpty ? block.text.trimRight() : block.text;
    markdown += body;
    for (final index in indexes) {
      markdown += '[citation:$index]';
    }
    markdown += block.text.substring(body.length);
  }
  return (markdown: markdown, text: text);
}

ReplyView buildReplyView(AssistantMessage reply, {required bool streaming}) {
  final results = <String, ReplyBlock>{};
  for (final block in reply.blocks) {
    if (block is WebSearchResultBlock || block is WebFetchResultBlock) {
      results[block is WebSearchResultBlock
              ? block.toolUseId
              : (block as WebFetchResultBlock).toolUseId] =
          block;
    }
  }

  final registry = SourceRegistry();
  final searchResults = <ReplySource>[];
  final steps = <ReplyStep>[];
  final mergedSearch = <String, SearchStep>{};
  ThinkingStep? mergedThinking;
  var pendingText = <({int index, String text, List<Citation> citations})>[];

  // Number sources in the order results appear in the reply, independent of
  // where citations reference them.
  for (final block in reply.blocks) {
    if (block is! ServerToolUseBlock) continue;
    final result = results[block.id];
    if (result is WebSearchResultBlock) {
      for (final item in result.content) {
        if (item is Map && item['type'] == 'web_search_result') {
          final source = registry.add(
            item['url'] is String ? item['url'] as String : '',
            item['title'] is String ? item['title'] as String : null,
            publishedAt: item['page_age'] is String
                ? item['page_age'] as String
                : null,
            snippet: item['snippet'] is String
                ? item['snippet'] as String
                : null,
            siteIcon: item['site_icon'] is String
                ? item['site_icon'] as String
                : null,
            siteName: item['site_name'] is String
                ? item['site_name'] as String
                : null,
          );
          if (!searchResults.contains(source)) {
            searchResults.add(source);
          }
        }
      }
    } else if (result is WebFetchResultBlock &&
        !result.failed &&
        block.kind == 'deep_search') {
      final fetched = result.result;
      if (fetched != null) {
        registry.add(
          result.url,
          result.title,
          publishedAt: fetched['published_at'] is String
              ? fetched['published_at'] as String
              : null,
        );
      }
    }
  }

  void flushPreamble() {
    if (pendingText.isEmpty) return;
    final joined = _joinText(
      pendingText
          .map((item) => (text: item.text, citations: item.citations))
          .toList(),
      registry,
    );
    if (joined.markdown.trim().isNotEmpty) {
      steps.add(TextStep('text-${pendingText.first.index}', joined.markdown));
    }
    pendingText = [];
  }

  for (var index = 0; index < reply.blocks.length; index++) {
    final block = reply.blocks[index];
    if (block is TextBlock && block.isTemplate) continue;
    if (block is! ThinkingBlock) mergedThinking = null;

    if (block is TextBlock) {
      pendingText.add((
        index: index,
        text: block.text,
        citations: block.citations,
      ));
      continue;
    }

    if (block is ThinkingBlock) {
      if (mergedThinking != null) {
        mergedThinking.blocks.add(block);
      } else if (block.thinking.isNotEmpty) {
        flushPreamble();
        mergedThinking = ThinkingStep('thinking-$index', [block]);
        steps.add(mergedThinking);
      }
      continue;
    }

    if (block is! ServerToolUseBlock) continue;
    final result = results[block.id];
    final fetched = result is WebFetchResultBlock ? result.result : null;
    final hasUrl =
        block.input['url'] is String &&
        (block.input['url'] as String).isNotEmpty;
    final fetchedUrl = fetched?['url'] is String
        ? fetched!['url'] as String
        : '';
    if (block.action == 'read_link' && !hasUrl && fetchedUrl.isEmpty) {
      continue;
    }
    flushPreamble();

    final status = _statusOf(
      result is WebSearchResultBlock ? result : null,
      result is WebFetchResultBlock ? result : null,
      streaming,
    );
    final last = steps.isEmpty ? null : steps.last;

    if (block.action == 'search') {
      final found = result is WebSearchResultBlock
          ? result.content
                .whereType<Map>()
                .where((item) => item['type'] == 'web_search_result')
                .map(
                  (item) => registry.add(
                    item['url'] is String ? item['url'] as String : '',
                    item['title'] is String ? item['title'] as String : null,
                    publishedAt: item['page_age'] is String
                        ? item['page_age'] as String
                        : null,
                    snippet: item['snippet'] is String
                        ? item['snippet'] as String
                        : null,
                    siteIcon: item['site_icon'] is String
                        ? item['site_icon'] as String
                        : null,
                    siteName: item['site_name'] is String
                        ? item['site_name'] as String
                        : null,
                  ),
                )
                .toList()
          : <ReplySource>[];

      final SearchStep? target;
      if (_isDeepSearch(block.kind)) {
        target = last is SearchStep && last.kind == block.kind ? last : null;
      } else {
        target = mergedSearch[block.kind];
      }
      if (target != null) {
        target.queries.addAll(block.queries);
        for (final source in found) {
          if (!target.results.contains(source)) target.results.add(source);
        }
        target.status = _mergeStatus([target.status, status]);
      } else {
        final step = SearchStep(
          key: block.id,
          kind: block.kind,
          queries: [...block.queries],
          results: found,
          status: status,
        );
        steps.add(step);
        if (!_isDeepSearch(block.kind)) {
          mergedSearch[block.kind] = step;
        }
      }
      continue;
    }

    final fetchedContent = fetched?['content'];
    final fetchedTitle =
        fetchedContent is Map && fetchedContent['title'] is String
        ? fetchedContent['title'] as String
        : null;
    final page = PageItem(
      id: block.id,
      url: block.url.isNotEmpty ? block.url : fetchedUrl,
      title: fetchedTitle ?? block.url,
      status: status,
    );
    if (block.action == 'read_link') {
      if (status != ToolStatus.wip) continue;
      if (last is ReadLinkStep) {
        last.links.add(page);
      } else {
        steps.add(ReadLinkStep([page]));
      }
    } else if (block.action == 'open_page') {
      if (last is OpenPageStep) {
        last.pages.add(page);
      } else {
        steps.add(OpenPageStep([page]));
      }
    } else {
      final item = PatternItem(
        id: block.id,
        pattern: block.pattern,
        status: status,
      );
      if (last is FindInPageStep) {
        last.patterns.add(item);
      } else {
        steps.add(FindInPageStep([item]));
      }
    }
  }

  final answer = pendingText.isEmpty
      ? null
      : _joinText(
          pendingText
              .map((item) => (text: item.text, citations: item.citations))
              .toList(),
          registry,
        );

  return ReplyView(
    steps: steps,
    answerMarkdown: answer != null && answer.text.isNotEmpty
        ? answer.markdown
        : null,
    answerText: answer?.text ?? '',
    sources: registry.list,
    searchResults: searchResults,
  );
}

String toolStatusTitle(
  ReplyView view,
  bool streaming,
  bool hasAnswer,
  bool zh,
) {
  if (hasAnswer) {
    final seconds = view.thinkingSeconds;
    if (seconds == null) return zh ? '深度思考' : 'DeepThink';
    return zh ? '已思考 $seconds 秒' : 'Thought for $seconds seconds';
  }
  if (!streaming) return zh ? '已停止思考' : 'Thinking stopped';
  final last = view.steps.isEmpty ? null : view.steps.last;
  if (last is SearchStep && last.status == ToolStatus.wip) {
    return _isImageSearch(last.kind)
        ? (zh ? '正在图片搜索…' : 'Searching images…')
        : (zh ? '正在搜索…' : 'Searching…');
  }
  if (last is OpenPageStep &&
      last.pages.any((page) => page.status == ToolStatus.wip)) {
    return zh ? '正在打开网页…' : 'Opening page…';
  }
  if (last is FindInPageStep &&
      last.patterns.any((item) => item.status == ToolStatus.wip)) {
    return zh ? '正在打开网页…' : 'Opening page…';
  }
  if (last is ReadLinkStep &&
      last.links.any((link) => link.status == ToolStatus.wip)) {
    return zh ? '正在阅读链接…' : 'Reading link…';
  }
  return zh ? '思考中…' : 'Thinking…';
}
