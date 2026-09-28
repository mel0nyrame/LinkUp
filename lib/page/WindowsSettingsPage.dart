import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';

class WindowsSettingsPage extends StatefulWidget {
  const WindowsSettingsPage({super.key, required this.configuration});

  final ConfigManager configuration;

  @override
  State<WindowsSettingsPage> createState() => _WindowsSettingsPageState();
}

class _WindowsSettingsPageState extends State<WindowsSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _userTypeController = TextEditingController();
  final _acidController = TextEditingController(text: defaultAcid);
  final _authServerController = TextEditingController(text: defaultAuthServer);

  bool _autoAcid = true;
  bool _hasConfiguration = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.clear();
    _passwordController.dispose();
    _userTypeController.dispose();
    _acidController.dispose();
    _authServerController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final facts = await widget.configuration.loadFacts();
      if (!mounted) return;
      setState(() {
        _hasConfiguration = facts != null;
        if (facts != null) {
          _usernameController.text = facts.username;
          _userTypeController.text = facts.userType;
          _autoAcid = facts.autoAcid;
          _acidController.text = facts.acid;
          _authServerController.text = facts.authServer;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final acid = _acidController.text.trim();
    final authServer = _authServerController.text.trim();
    bool saved;
    try {
      if (_hasConfiguration) {
        saved = await widget.configuration.update(
          ConfigUpdate(
            username: username,
            password: password.isEmpty ? null : password,
            userType: _userTypeController.text.trim(),
            acid: acid,
            autoAcid: _autoAcid,
            authServer: authServer,
          ),
        );
      } else {
        saved = await widget.configuration.save(
          AuthConfig(
            username: username,
            password: password,
            userType: _userTypeController.text.trim(),
            acid: acid,
            hasExplicitAcid: acid.isNotEmpty,
            autoAcid: _autoAcid,
            authServer: authServer,
          ),
        );
      }
    } catch (_) {
      saved = false;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _hasConfiguration = true;
    });

    if (saved) {
      _passwordController.clear();
      _showMessage('配置已保存');
    } else {
      _showMessage('保存失败，请确认 Windows 安全存储可用后重试。');
    }
  }

  Future<void> _deleteConfiguration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号配置？'),
        content: const Text('账号信息和安全存储中的密码都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除配置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    bool deleted;
    try {
      deleted = await widget.configuration.delete();
    } catch (_) {
      deleted = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!deleted) {
      _showMessage('删除失败，请重试。');
      return;
    }

    _usernameController.clear();
    _passwordController.clear();
    _userTypeController.clear();
    _acidController.text = defaultAcid;
    _authServerController.text = defaultAuthServer;
    setState(() {
      _hasConfiguration = false;
      _autoAcid = true;
    });
    _showMessage('账号配置已删除');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadFailed
                ? _buildLoadError(context)
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('账号与网络', style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 6),
                        Text(
                          '账号资料保存在本机，密码由 Windows 安全存储保护。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _buildAccountSection(context),
                        const SizedBox(height: 16),
                        _buildNetworkSection(context),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            FilledButton.icon(
                              key: const ValueKey('windows-save-configuration'),
                              onPressed: _saving ? null : _saveConfiguration,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(_saving ? '保存中…' : '保存配置'),
                            ),
                            if (_hasConfiguration) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                key: const ValueKey(
                                  'windows-delete-configuration',
                                ),
                                onPressed: _saving
                                    ? null
                                    : _deleteConfiguration,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('删除配置'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('账号与网络', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error),
                const SizedBox(width: 12),
                const Expanded(child: Text('无法读取本地配置，请重试。')),
                TextButton(
                  onPressed: _loadConfiguration,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('账号信息', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '编辑时密码留空会保留当前密码。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('windows-username'),
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '请输入学号或工号',
                border: OutlineInputBorder(),
              ),
              validator: (_) =>
                  _usernameController.text.trim().isEmpty ? '请输入用户名' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('windows-password'),
              controller: _passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: _hasConfiguration ? '留空则保留当前密码' : '请输入密码',
                border: const OutlineInputBorder(),
              ),
              validator: (_) =>
                  !_hasConfiguration && _passwordController.text.isEmpty
                  ? '请输入密码'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('windows-user-type'),
              controller: _userTypeController,
              decoration: const InputDecoration(
                labelText: '运营商类型（选填）',
                hintText: '如 cmcc、unicom 或 telecom',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('认证网络', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动获取 ACID'),
              subtitle: Text(_autoAcid ? '自动探测可用接入点' : '使用下方指定的接入点 ID'),
              value: _autoAcid,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _autoAcid = value),
            ),
            if (!_autoAcid) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('windows-acid'),
                controller: _acidController,
                decoration: const InputDecoration(
                  labelText: 'ACID（接入点 ID）',
                  hintText: '请输入 ACID',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (_) =>
                    !_autoAcid && _acidController.text.trim().isEmpty
                    ? '请输入 ACID'
                    : null,
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('windows-auth-server'),
              controller: _authServerController,
              decoration: InputDecoration(
                labelText: '认证服务器',
                hintText: defaultAuthServer,
                helperText: '留空时使用默认服务器 $defaultAuthServer',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                final server = value?.trim() ?? '';
                if (server.isNotEmpty &&
                    !RegExp(r'^[0-9a-zA-Z.-]+$').hasMatch(server)) {
                  return '请输入 IP 地址或域名';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
