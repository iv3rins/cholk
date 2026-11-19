import 'dart:async';
import 'dart:convert';

import 'package:deepseek_chat/api/account_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('normalizes HTTPS and permits HTTP only for local development', () {
    expect(
      normalizeServerAddress(' https://example.com/base/// '),
      'https://example.com/base',
    );
    expect(
      normalizeServerAddress('http://localhost:8080/'),
      'http://localhost:8080',
    );
    expect(
      normalizeServerAddress('http://127.0.0.1:8000'),
      'http://127.0.0.1:8000',
    );
    for (final value in [
      'http://example.com',
      'example.com',
      'ftp://example.com',
      'https:///missing-host',
      'https://user:secret@example.com',
      'https://example.com/?token=secret',
      'https://example.com/#secret',
    ]) {
      expect(
        () => normalizeServerAddress(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test(
    'login sends the frozen payloads and stores only an in-memory session',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/auth/login' => jsonResponse({
            'username': 'alice',
            'token': 'memory-token',
          }),
          '/v1/models' => jsonResponse({
            'data': [
              {'id': 'model-a', 'object': 'model'},
              {'id': 'model-b'},
            ],
          }),
          _ => http.Response('unexpected', 404),
        };
      });
      final account = AccountClient(httpClient: client);
      addTearDown(account.dispose);
      var notifications = 0;
      account.addListener(() => notifications++);

      await account.authenticate(
        'https://example.com/',
        username: ' alice ',
        password: 'not-persisted',
        register: false,
      );

      expect(account.address, 'https://example.com');
      expect(account.username, 'alice');
      expect(account.token, 'memory-token');
      expect(account.models, ['model-a', 'model-b']);
      expect(notifications, 1);
      expect(requests, hasLength(2));
      expect(requests.first.method, 'POST');
      expect(jsonDecode(requests.first.body), {
        'username': 'alice',
        'password': 'not-persisted',
      });
      expect(
        requests.first.headers['content-type'],
        contains('application/json'),
      );
      expect(requests.last.method, 'GET');
      expect(requests.last.headers['authorization'], 'Bearer memory-token');
    },
  );

  test(
    'register uses /auth/register and rejects malformed model responses',
    () async {
      final account = AccountClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/register') {
            return jsonResponse({'username': 'new-user', 'token': 'token'});
          }
          return jsonResponse({
            'data': [
              {'object': 'model'},
            ],
          });
        }),
      );
      addTearDown(account.dispose);

      await expectLater(
        account.authenticate(
          'http://localhost:8000',
          username: 'new-user',
          password: 'pw',
          register: true,
        ),
        throwsA(
          isA<AccountException>().having(
            (error) => error.code,
            'code',
            'invalidResponse',
          ),
        ),
      );
      expect(account.token, isNull);
      expect(account.address, isNull);
      expect(account.models, isEmpty);
    },
  );

  test('logout clears immediately and sends Bearer to /auth/logout', () async {
    final logout = Completer<http.Response>();
    http.Request? logoutRequest;
    final account = AccountClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return jsonResponse({'username': 'alice', 'token': 'secret'});
        }
        if (request.url.path == '/v1/models') {
          return jsonResponse({
            'data': [
              {'id': 'model'},
            ],
          });
        }
        logoutRequest = request;
        return logout.future;
      }),
    );
    addTearDown(account.dispose);
    await account.authenticate(
      'https://example.com',
      username: 'alice',
      password: 'pw',
      register: false,
    );
    final pending = account.logout();
    expect(account.token, isNull);
    expect(account.username, isNull);
    expect(account.address, isNull);
    expect(account.models, isEmpty);
    logout.complete(http.Response('', 204));
    await pending;
    expect(logoutRequest!.url.path, '/auth/logout');
    expect(logoutRequest!.method, 'POST');
    expect(logoutRequest!.headers['authorization'], 'Bearer secret');
  });

  test('clearSession makes a stale authentication response harmless', () async {
    final login = Completer<http.Response>();
    final account = AccountClient(httpClient: MockClient((_) => login.future));
    addTearDown(account.dispose);
    final pending = account.authenticate(
      'https://example.com',
      username: 'alice',
      password: 'pw',
      register: false,
    );
    account.clearSession();
    login.complete(jsonResponse({'username': 'alice', 'token': 'stale'}));
    await pending;
    expect(account.token, isNull);
    expect(account.username, isNull);
    expect(account.address, isNull);
    expect(account.models, isEmpty);
  });

  test('an older login cannot replace a newer session', () async {
    final firstLogin = Completer<http.Response>();
    final account = AccountClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return request.body.contains('first')
              ? firstLogin.future
              : jsonResponse({'username': 'second', 'token': 'new-token'});
        }
        return jsonResponse({
          'data': [
            {'id': 'new-model'},
          ],
        });
      }),
    );
    addTearDown(account.dispose);
    final stale = account.authenticate(
      'https://example.com',
      username: 'first',
      password: 'pw',
      register: false,
    );
    await account.authenticate(
      'https://example.com',
      username: 'second',
      password: 'pw',
      register: false,
    );
    firstLogin.complete(
      jsonResponse({'username': 'first', 'token': 'old-token'}),
    );
    await stale;
    expect(account.username, 'second');
    expect(account.token, 'new-token');
    expect(account.models, ['new-model']);
  });

  test('account routes never follow redirects', () async {
    final seen = <String>[];
    var mode = 'login';
    final account = AccountClient(
      httpClient: MockClient((request) async {
        seen.add(
          '${request.method} ${request.url.path} '
          'follow=${request.followRedirects} '
          'auth=${request.headers['authorization'] ?? '-'}',
        );
        if (request.url.path == '/auth/login') {
          return jsonResponse({'username': 'alice', 'token': 'secret'});
        }
        return switch (mode) {
          // A redirect must surface as a status, never be replayed elsewhere.
          'models-redirect' => http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example.com/v1/models'},
          ),
          'logout-redirect' => http.Response(
            '',
            307,
            headers: {'location': 'https://evil.example.com/auth/logout'},
          ),
          _ => jsonResponse({
            'data': [
              {'id': 'model'},
            ],
          }),
        };
      }),
    );
    addTearDown(account.dispose);

    mode = 'models-redirect';
    await expectLater(
      account.authenticate(
        'https://example.com',
        username: 'alice',
        password: 'pw',
        register: false,
      ),
      throwsA(
        isA<AccountException>().having(
          (error) => error.statusCode,
          'status',
          302,
        ),
      ),
    );
    expect(account.token, isNull);
    // Only the two account routes were contacted; no follow-up request exists.
    expect(seen, hasLength(2));

    mode = 'ok';
    await account.authenticate(
      'https://example.com',
      username: 'alice',
      password: 'pw',
      register: false,
    );
    seen.clear();
    mode = 'logout-redirect';
    await expectLater(
      account.logout(),
      throwsA(
        isA<AccountException>().having(
          (error) => error.statusCode,
          'status',
          307,
        ),
      ),
    );
    expect(seen, ['POST /auth/logout follow=false auth=Bearer secret']);

    // The login body itself must not be replayed through a redirect either.
    expect(
      seen,
      everyElement(contains('follow=false')),
      reason: 'every account request disables redirects',
    );
  });

  test(
    'a redirected login is refused instead of replaying the password',
    () async {
      final seen = <String>[];
      final account = AccountClient(
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          return http.Response(
            '',
            307,
            headers: {'location': 'https://evil.example.com/auth/login'},
          );
        }),
      );
      addTearDown(account.dispose);

      await expectLater(
        account.authenticate(
          'https://example.com',
          username: 'alice',
          password: 'pw',
          register: false,
        ),
        throwsA(
          isA<AccountException>().having(
            (error) => error.statusCode,
            'status',
            307,
          ),
        ),
      );
      expect(seen, ['POST /auth/login']);
      expect(account.token, isNull);
    },
  );

  test('an account request times out even when its body has started', () async {
    final aborted = Completer<void>();
    final account = AccountClient(
      requestTimeout: const Duration(milliseconds: 30),
      httpClient: MockClient.streaming((request, _) async {
        final abortTrigger = (request as http.AbortableRequest).abortTrigger!;
        Stream<List<int>> stalledBody() async* {
          yield utf8.encode('{');
          await abortTrigger;
          aborted.complete();
        }

        return http.StreamedResponse(stalledBody(), 200);
      }),
    );
    addTearDown(account.dispose);

    await expectLater(
      account.authenticate(
        'https://example.com',
        username: 'alice',
        password: 'password',
        register: false,
      ),
      throwsA(
        isA<AccountException>().having(
          (error) => error.code,
          'code',
          'network',
        ),
      ),
    );
    await aborted.future;
    expect(account.token, isNull);
  });

  test('HTTP errors do not create a session', () async {
    final account = AccountClient(
      httpClient: MockClient(
        (_) async => jsonResponse({'error': 'invalid'}, 401),
      ),
    );
    addTearDown(account.dispose);
    await expectLater(
      account.authenticate(
        'https://example.com',
        username: 'alice',
        password: 'bad',
        register: false,
      ),
      throwsA(
        isA<AccountException>().having(
          (error) => error.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(account.token, isNull);
    expect(account.models, isEmpty);
  });
}
