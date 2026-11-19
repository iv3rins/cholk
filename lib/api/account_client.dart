import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Normalizes a server base URL without retaining any account credentials.
///
/// Remote servers must use HTTPS. Plain HTTP is limited to local development.
String normalizeServerAddress(String value) {
  final input = value.trim();
  final Uri uri;
  try {
    uri = Uri.parse(input);
  } on FormatException {
    throw const FormatException('Invalid server address');
  }
  final local = const {
    'localhost',
    '127.0.0.1',
    '::1',
  }.contains(uri.host.toLowerCase());
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && local))) {
    throw const FormatException(
      'Use an HTTPS server address, or HTTP on localhost',
    );
  }
  return uri.toString().replaceAll(RegExp(r'/+$'), '');
}

class AccountException implements Exception {
  const AccountException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => 'AccountException($code, $statusCode)';
}

/// Authentication state is deliberately memory-only: reopening the app requires
/// signing in again. A generation counter prevents stale responses from
/// restoring a session after logout or a newer authentication attempt.
class AccountClient extends ChangeNotifier {
  AccountClient({
    http.Client? httpClient,
    this._requestTimeout = const Duration(seconds: 40),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration _requestTimeout;
  int _generation = 0;
  bool _disposed = false;
  String? _address;
  String? _username;
  String? _token;
  List<String> _models = const [];

  String? get address => _address;
  String? get username => _username;
  String? get token => _token;
  List<String> get models => List.unmodifiable(_models);

  Uri _uri(String base, String path) => Uri.parse('$base$path');

  /// Account routes never follow redirects: a redirect would replay the token
  /// or the password at a host the user did not enter.
  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(headers ?? const {});
    if (body != null) request.body = body;
    try {
      return await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_requestTimeout);
    } on TimeoutException {
      abort.complete();
      throw const AccountException('network');
    } on http.ClientException {
      throw const AccountException('network');
    }
  }

  Future<void> authenticate(
    String address, {
    required String username,
    required String password,
    required bool register,
  }) async {
    final generation = ++_generation;
    _clearLocalSession();
    final normalized = normalizeServerAddress(address);
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      throw const AccountException('credentials');
    }
    final response = await _request(
      'POST',
      _uri(normalized, register ? '/auth/register' : '/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': name, 'password': password}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AccountException('http', statusCode: response.statusCode);
    }
    final payload = _jsonObject(response.body);
    final responseName = payload?['username'];
    final responseToken = payload?['token'];
    if (responseName is! String ||
        responseName.isEmpty ||
        responseToken is! String ||
        responseToken.isEmpty) {
      throw const AccountException('invalidResponse');
    }
    if (generation != _generation || _disposed) return;
    final modelsResponse = await _request(
      'GET',
      _uri(normalized, '/v1/models'),
      headers: {'Authorization': 'Bearer $responseToken'},
    );
    if (modelsResponse.statusCode != 200) {
      throw AccountException('http', statusCode: modelsResponse.statusCode);
    }
    final modelsPayload = _jsonObject(modelsResponse.body);
    final data = modelsPayload?['data'];
    if (data is! List ||
        data.any(
          (entry) =>
              entry is! Map ||
              entry['id'] is! String ||
              (entry['id'] as String).isEmpty,
        )) {
      throw const AccountException('invalidResponse');
    }
    if (generation != _generation || _disposed) return;
    _address = normalized;
    _username = responseName;
    _token = responseToken;
    _models = [for (final entry in data) entry['id'] as String];
    notifyListeners();
  }

  Future<void> logout() async {
    final currentAddress = _address;
    final currentToken = _token;
    ++_generation;
    _clearLocalSession();
    if (currentAddress == null || currentToken == null) return;
    final response = await _request(
      'POST',
      _uri(currentAddress, '/auth/logout'),
      headers: {'Authorization': 'Bearer $currentToken'},
    );
    if (response.statusCode != 204) {
      throw AccountException('http', statusCode: response.statusCode);
    }
  }

  /// Immediately revokes the in-memory credential and invalidates in-flight
  /// authentication/logout responses without performing a network request.
  void clearSession() {
    ++_generation;
    _clearLocalSession();
  }

  void _clearLocalSession() {
    final changed =
        _address != null ||
        _username != null ||
        _token != null ||
        _models.isNotEmpty;
    _address = null;
    _username = null;
    _token = null;
    _models = const [];
    if (changed && !_disposed) notifyListeners();
  }

  Map<String, dynamic>? _jsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _address = null;
    _username = null;
    _token = null;
    _models = const [];
    _http.close();
    super.dispose();
  }
}
