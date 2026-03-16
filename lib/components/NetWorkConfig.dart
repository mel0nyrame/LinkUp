// Powered By Kimi
// 这真不会写
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';

class NetworkConfigCard extends StatefulWidget {
  const NetworkConfigCard({super.key});

  @override
  State<NetworkConfigCard> createState() => _NetworkConfigCardState();
}

class _NetworkConfigCardState extends State<NetworkConfigCard> {
  bool _autoAcid = true;
  final _acidCtrl = TextEditingController(text: '1');
  final _authServerCtrl = TextEditingController(text: '10.129.1.1');
  String _displayAcid = '1';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _acidCtrl.dispose();
    _authServerCtrl.dispose();
    super.dispose();
  }

  // 加载配置
  Future<void> _loadConfig() async {
    final config = await ConfigUtil.loadConfig();
    if (config != null) {
      setState(() {
        _autoAcid = config['auto_acid'] ?? true;
        _displayAcid = config['acid'] ?? '1';
        _acidCtrl.text = _displayAcid;
        _authServerCtrl.text = config['auth_server'] ?? '10.129.1.1';
      });
    }
  }

  // 保存配置
  Future<void> _saveConfig() async {
    final config = await ConfigUtil.loadConfig();
    if (config != null) {
      await ConfigUtil.saveConfig(
        username: config['username'] ?? '',
        password: config['password'] ?? '',
        acid: _acidCtrl.text,
        autoAcid: _autoAcid,
        authServer: _authServerCtrl.text,
      );
    }
  }

  // 保存认证服务器
  Future<void> _saveAuthServer() async {
    final config = await ConfigUtil.loadConfig();
    if (config != null) {
      await ConfigUtil.saveConfig(
        username: config['username'] ?? '',
        password: config['password'] ?? '',
        acid: config['acid'] ?? '1',
        autoAcid: config['auto_acid'] ?? true,
        authServer: _authServerCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('认证服务器已更新，下次登录生效')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_ethernet, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '网络配置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动获取 ACID'),
              subtitle: Text(
                _autoAcid 
                    ? '系统将自动尝试可用接入点' 
                    : '手动指定接入点 ID',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              value: _autoAcid,
              onChanged: (value) {
                setState(() {
                  _autoAcid = value;
                });
                _saveConfig();
              },
              secondary: Icon(
                _autoAcid ? Icons.auto_fix_high : Icons.edit,
                color: colorScheme.primary,
              ),
            ),

            const Divider(height: 8),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _autoAcid 
                  ? CrossFadeState.showFirst 
                  : CrossFadeState.showSecond,
              firstChild: _buildAutoModeView(context),
              secondChild: _buildManualInputView(context),
            ),
            
            const Divider(height: 24),

            // 认证服务器设置
            _buildAuthServerInput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoModeView(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade600,
            size: 20,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前接入点',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'ACID:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 6, right: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _displayAcid,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.only(
                        top: 2,
                        bottom: 2,
                        left: 6,
                        right: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '自动',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _acidCtrl,
        onChanged: (value) {
          _displayAcid = value;
          _saveConfig();
        },
        decoration: InputDecoration(
          labelText: 'ACID (接入点 ID)',
          hintText: '如: 1, 2, 5, 11, 15',
          prefixIcon: const Icon(Icons.place_outlined),
          border: const OutlineInputBorder(),
          helperStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置为默认值',
            onPressed: () {
              setState(() {
                _acidCtrl.text = '1';
                _displayAcid = '1';
              });
              _saveConfig();
            },
          ),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
      ),
    );
  }

  Widget _buildAuthServerInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dns_outlined, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              '认证服务器',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '配置校园网认证服务器地址，切换不同 WiFi 时可能需要修改',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _authServerCtrl,
          onSubmitted: (_) => _saveAuthServer(),
          decoration: InputDecoration(
            labelText: '服务器地址',
            hintText: '如: 10.129.1.1',
            prefixIcon: const Icon(Icons.dns_outlined),
            border: const OutlineInputBorder(),
            helperText: '默认: 10.129.1.1,按回车保存',
            helperStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: '保存',
                  onPressed: _saveAuthServer,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '恢复默认',
                  onPressed: () {
                    setState(() {
                      _authServerCtrl.text = '10.129.1.1';
                    });
                    _saveAuthServer();
                  },
                ),
              ],
            ),
          ),
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}
