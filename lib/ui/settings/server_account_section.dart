import 'package:material_ui/material_ui.dart';

import '../../api/account_client.dart';
import '../../models/app_settings.dart';
import '../app_scope.dart';
import 'settings_frame.dart';

/// Account forms keep passwords in their controller only for the current draft.
/// AccountClient owns the token in memory; SettingsStore receives only the URL.
class ServerAccountSection extends StatefulWidget {
  const ServerAccountSection({super.key});

  @override
  State<ServerAccountSection> createState() => _ServerAccountSectionState();
}

class _ServerAccountSectionState extends State<ServerAccountSection> {
  late final TextEditingController _address;
  final _username = TextEditingController();
  final _password = TextEditingController();
  AccountClient? _account;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    final account = scope.controller.account;
    if (_account == account) return;
    _account?.removeListener(_accountChanged);
    _account = account;
    _account!.addListener(_accountChanged);
    _address = TextEditingController(
      text: scope.controller.settings.serverAddress,
    );
  }

  void _accountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _account?.removeListener(_accountChanged);
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String _message(Object error, bool zh) {
    if (error is FormatException) {
      return zh
          ? '请输入有效的 HTTPS 服务器地址；仅 localhost 开发可使用 HTTP。'
          : 'Enter a valid HTTPS server address. HTTP is allowed only for localhost development.';
    }
    if (error is AccountException) {
      if (error.code == 'credentials') {
        return zh ? '请输入账号和密码。' : 'Enter your username and password.';
      }
      if (error.code == 'network') {
        return zh
            ? '无法连接服务器，请检查地址后重试。'
            : 'Could not connect. Check the server address and try again.';
      }
      if (error.code == 'invalidResponse') {
        return zh
            ? '服务器返回了无效的账号或模型数据。'
            : 'The server returned invalid account or model data.';
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return zh
            ? '账号或密码不正确，或登录已失效。'
            : 'Incorrect username or password, or the session is no longer valid.';
      }
      if (error.statusCode == 409) {
        return zh
            ? '该账号已存在，请直接登录。'
            : 'This username already exists. Please sign in.';
      }
      return zh
          ? '服务器请求失败（HTTP ${error.statusCode ?? '未知'}）。'
          : 'Server request failed (HTTP ${error.statusCode ?? 'unknown'}).';
    }
    return zh ? '设置保存失败，请重试。' : 'Could not save settings. Please try again.';
  }

  Future<void> _saveAddress() async {
    if (_busy) return;
    final zh = AppScope.of(context).controller.settings.isZh;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final input = _address.text.trim();
      final normalized = input.isEmpty ? '' : normalizeServerAddress(input);
      await AppScope.of(context).controller.setServerAddress(normalized);
      if (!mounted) return;
      _address.text = normalized;
    } catch (error) {
      if (mounted) _error = _message(error, zh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate({required bool register}) async {
    if (_busy) return;
    final scope = AppScope.of(context);
    final zh = scope.controller.settings.isZh;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await scope.controller.account.authenticate(
        _address.text,
        username: _username.text,
        password: _password.text,
        register: register,
      );
      final address = scope.controller.account.address;
      if (address == null) return;
      await scope.controller.setServerAddress(address);
      if (!mounted) return;
      _password.clear();
      _address.text = address;
    } catch (error) {
      if (mounted) _error = _message(error, zh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    final zh = AppScope.of(context).controller.settings.isZh;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).controller.account.logout();
    } catch (error) {
      if (mounted) _error = _message(error, zh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final zh = scope.controller.settings.isZh;
    final account = scope.controller.account;
    final signedIn = account.token != null;
    const accountButtonSize = Size(88, 44);
    final collapseAddress =
        defaultAccountOrigin.isNotEmpty &&
        !scope.controller.settings.isAdvancedMode;
    final addressFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          key: const Key('server-address'),
          controller: _address,
          enabled: !_busy && !signedIn,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: zh ? '服务器地址' : 'Server address',
            hintText: 'https://example.com',
            helperText: zh ? '仅保存地址；密码和登录令牌不会写入设备设置。' : 'Only the address is saved. Passwords and tokens are never stored in settings.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 10),
        if (!signedIn)
          TextButton(
            key: const Key('server-address-save'),
            onPressed: _busy ? null : _saveAddress,
            child: Text(zh ? '保存服务器地址' : 'Save server address'),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(zh ? '账号' : 'Account'),
        if (!collapseAddress) addressFields,
        if (signedIn) ...[
          Text(
            zh ? '已登录：${account.username}' : 'Signed in as ${account.username}',
            key: const Key('account-signed-in'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('account-logout'),
              onPressed: _busy ? null : _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(zh ? '登出' : 'Sign out'),
            ),
          ),
        ] else ...[
          TextField(
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            key: const Key('account-username'),
            controller: _username,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(labelText: zh ? '账号' : 'Username'),
          ),
          const SizedBox(height: 10),
          TextField(
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            key: const Key('account-password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: zh ? '密码' : 'Password'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('account-login'),
                style: FilledButton.styleFrom(minimumSize: accountButtonSize),
                onPressed: _busy ? null : () => _authenticate(register: false),
                child: Text(zh ? '登录' : 'Sign in'),
              ),
              OutlinedButton(
                key: const Key('account-register'),
                style: OutlinedButton.styleFrom(minimumSize: accountButtonSize),
                onPressed: _busy ? null : () => _authenticate(register: true),
                child: Text(zh ? '注册' : 'Register'),
              ),
            ],
          ),
        ],
        if (collapseAddress)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            minTileHeight: 44,
            title: Text(scope.strings.advanced),
            children: [addressFields],
          ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const Key('account-error'),
              style: TextStyle(color: scope.palette.signal, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
