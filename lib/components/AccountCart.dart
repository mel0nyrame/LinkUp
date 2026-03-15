import 'package:flutter/material.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';

class Accountcart extends StatefulWidget {
  final VoidCallback? onConfigChanged;

  const Accountcart({super.key, this.onConfigChanged});

  @override
  State<Accountcart> createState() => _AccountcartState();
}

class _AccountcartState extends State<Accountcart> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = true;
  String? _acid;
  bool? _autoAcid;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // 加载当前配置
  Future<void> _loadCurrentConfig() async {
    final config = await ConfigUtil.loadConfig();
    if (config != null) {
      setState(() {
        _usernameCtrl.text = config['username'] ?? '';
        _passwordCtrl.text = config['password'] ?? '';
        _acid = config['acid'] ?? '1';
        _autoAcid = config['auto_acid'] ?? true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 保存配置（覆盖原有）
  Future<void> _saveConfig() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('学号和密码不能为空'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await ConfigUtil.saveConfig(
      username: username,
      password: password,
      acid: _acid ?? '1',
      autoAcid: _autoAcid ?? true,
    );

    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存'), backgroundColor: Colors.green),
      );
      widget.onConfigChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败，请检查权限'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 删除配置
  Future<void> _deleteConfig() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除保存的配置吗？这将清除学号和密码信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final success = await ConfigUtil.deleteConfig();

    setState(() => _isLoading = false);

    if (success) {
      setState(() {
        _usernameCtrl.clear();
        _passwordCtrl.clear();
        _acid = '1';
        _autoAcid = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已删除'), backgroundColor: Colors.green),
      );
      widget.onConfigChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '账号信息',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: '学号',
                hintText: '请输入学号',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16.0)),
                ),
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入密码',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16.0)),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              obscureText: _obscurePassword,
            ),
            const SizedBox(height: 24),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('保存配置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deleteConfig,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      '删除配置',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
