import http from 'node:http';

const port = Number(process.env.PORT ?? 8788);

const searchResults = [
  {
    type: 'web_search_result',
    url: 'https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html',
    title: 'StatefulWidget class',
    snippet: 'A widget that has mutable state.',
    site_name: 'api.flutter.dev',
    site_icon: null,
    encrypted_content: 'demo',
    page_age: null,
  },
  {
    type: 'web_search_result',
    url: 'https://docs.flutter.dev/ui/interactivity',
    title: 'Adding interactivity to your Flutter app',
    snippet: 'Learn how to add a stateful widget and call setState.',
    site_name: 'docs.flutter.dev',
    site_icon: null,
    encrypted_content: 'demo',
    page_age: null,
  },
];

const answer = [
  '## 一个简单的问候页面\n\n',
  '下面是一个使用 `StatefulWidget` 的示例，点击按钮会更新问候语。\n\n',
  '```dart\n',
  "class GreetingPage extends StatefulWidget {\n",
  '  const GreetingPage({super.key});\n\n',
  '  @override\n',
  '  State<GreetingPage> createState() => _GreetingPageState();\n',
  '}\n\n',
  'class _GreetingPageState extends State<GreetingPage> {\n',
  "  String _name = '世界';\n\n",
  '  @override\n',
  '  Widget build(BuildContext context) {\n',
  '    return Scaffold(\n',
  "      appBar: AppBar(title: const Text('问候')),\n",
  '      body: Center(\n',
  '        child: Column(\n',
  '          mainAxisSize: MainAxisSize.min,\n',
  '          children: [\n',
  "            Text('你好，$_name！'),\n",
  '            const SizedBox(height: 12),\n',
  '            FilledButton(\n',
  "              onPressed: () => setState(() => _name = 'Flutter'),\n",
  "              child: const Text('换个问候'),\n",
  '            ),\n',
  '          ],\n',
  '        ),\n',
  '      ),\n',
  '    );\n',
  '  }\n',
  '}\n',
  '```\n\n',
  '- `StatefulWidget` 负责保存可变状态\n',
  '- 调用 `setState` 后界面会重新构建\n',
  '- `const` 构造函数可以减少不必要的重建\n\n',
  '这是本地 mock 上游返回的示例内容，用来预览流式渲染效果。',
];

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
  });
}

function json(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': body.length,
  });
  res.end(body);
}

function lastUserText(body) {
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const message = messages[i];
    if (message?.role !== 'user') continue;
    if (typeof message.content === 'string') return message.content;
    if (Array.isArray(message.content)) {
      return message.content
        .filter((block) => block?.type === 'text')
        .map((block) => block.text)
        .join('');
    }
  }
  return '';
}

function streamMessage(req, res, body) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
  });

  let closed = false;
  const timers = [];
  const send = (event, payload) => {
    if (closed) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
  };
  const after = (ms, callback) => {
    timers.push(setTimeout(callback, ms));
  };
  const finish = () => {
    if (closed) return;
    closed = true;
    res.end();
  };
  res.on('close', () => {
    closed = true;
    for (const timer of timers) clearTimeout(timer);
  });

  const title = lastUserText(body).trim().slice(0, 28) || 'Flutter 界面预览';

  send('message_start', {
    type: 'message_start',
    message: {
      id: 'msg_demo_' + Date.now(),
      model: 'deepseek-flash',
      usage: {
        input_tokens: 1280,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        output_tokens: 0,
      },
    },
  });

  after(40, () => {
    send('content_block_start', {
      type: 'content_block_start',
      index: 0,
      content_block: { type: 'thinking', thinking: '' },
    });
    send('content_block_delta', {
      type: 'content_block_delta',
      index: 0,
      delta: {
        type: 'thinking_delta',
        thinking: '用户需要一个可以直接运行的 Flutter 页面示例，',
      },
    });
  });
  after(120, () => {
    send('content_block_delta', {
      type: 'content_block_delta',
      index: 0,
      delta: {
        type: 'thinking_delta',
        thinking: '还需要说明状态更新和按钮交互。先给出最小实现，再补充关键点。',
      },
    });
  });
  after(220, () => {
    send('content_block_delta', {
      type: 'content_block_delta',
      index: 0,
      delta: { type: 'signature_delta', signature: 'demo-signature' },
    });
    send('content_block_stop', { type: 'content_block_stop', index: 0 });
  });

  after(300, () => {
    send('content_block_start', {
      type: 'content_block_start',
      index: 1,
      content_block: {
        type: 'server_tool_use',
        id: 'srvtoolu_demo_1',
        name: 'deepseek_web_search',
        input: {
          action: 'search',
          queries: ['Flutter StatefulWidget 示例', 'Flutter setState 用法'],
        },
        caller: { type: 'direct' },
        kind: 'search',
      },
    });
    send('content_block_stop', { type: 'content_block_stop', index: 1 });
  });

  after(380, () => {
    send('content_block_start', {
      type: 'content_block_start',
      index: 2,
      content_block: {
        type: 'web_search_tool_result',
        tool_use_id: 'srvtoolu_demo_1',
        kind: 'search',
        content: searchResults,
      },
    });
    send('content_block_stop', { type: 'content_block_stop', index: 2 });
  });

  after(460, () => {
    send('content_block_start', {
      type: 'content_block_start',
      index: 3,
      content_block: { type: 'text', text: '' },
    });
    let delay = 520;
    for (const chunk of answer) {
      after(delay, () => {
        send('content_block_delta', {
          type: 'content_block_delta',
          index: 3,
          delta: { type: 'text_delta', text: chunk },
        });
      });
      delay += 22;
    }
    after(delay + 30, () => {
      send('content_block_delta', {
        type: 'content_block_delta',
        index: 3,
        delta: {
          type: 'citations_delta',
          citation: {
            type: 'web_search_result_location',
            url: 'https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html',
            title: 'StatefulWidget class',
            cited_text: '下面是一个使用 StatefulWidget 的示例',
            encrypted_index: '',
          },
        },
      });
      send('content_block_stop', { type: 'content_block_stop', index: 3 });
      send('message_delta', {
        type: 'message_delta',
        delta: {
          stop_reason: 'end_turn',
          stop_sequence: null,
          ...(body?.title?.enabled ? { title } : {}),
        },
        usage: {
          input_tokens: 1280,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 640,
        },
      });
      send('message_stop', { type: 'message_stop' });
      finish();
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/models') {
    json(res, 200, {
      object: 'list',
      data: [{ id: 'deepseek-flash', object: 'model' }],
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/anthropic/v1/messages') {
    const raw = await readBody(req);
    let body = {};
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      body = {};
    }
    streamMessage(req, res, body);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/anthropic/v1/files') {
    await readBody(req);
    json(res, 200, {
      id: 'file_demo_1',
      type: 'file',
      size_bytes: 5,
      created_at: new Date().toISOString(),
      filename: 'demo.txt',
      mime_type: 'text/plain',
    });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/v1/tools/asr') {
    await readBody(req);
    json(res, 200, { text: '这是本地 mock 返回的语音识别示例。' });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/v1/tools/tts') {
    await readBody(req);
    res.writeHead(200, { 'content-type': 'application/octet-stream' });
    res.end(Buffer.alloc(24000));
    return;
  }

  json(res, 404, { error: { message: 'mock upstream: not found' } });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`[mock] listening on http://127.0.0.1:${port}`);
});
