import 'dart:io';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';

class SystemSettingsCard extends StatefulWidget {
  const SystemSettingsCard({super.key});

  @override
  State<SystemSettingsCard> createState() => _SystemSettingsCardState();
}

class _SystemSettingsCardState extends State<SystemSettingsCard> {
  bool _keepAlive = true;
  bool _autoStart = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    await SystemSettingsUtil.init();
    setState(() {
      _keepAlive = SystemSettingsUtil.getKeepAlive();
      _autoStart = SystemSettingsUtil.getAutoStart();
      _isLoading = false;
    });
  }

  /// 设置保留后台
  Future<void> _setKeepAlive(bool value) async {
    setState(() => _isLoading = true);
    
    final success = await SystemSettingsUtil.setKeepAlive(value);
    
    if (mounted) {
      setState(() {
        _keepAlive = value;
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value 
              ? '后台运行已开启' 
              : '后台运行已关闭'),
          duration: const Duration(seconds: 2),
        ),
      );
      
      // 如果开启后台运行，提示用户添加电池白名单
      if (value && Platform.isAndroid) {
        _showBatteryOptimizationDialog();
      }
    }
  }

  /// 设置开机自启
  Future<void> _setAutoStart(bool value) async {
    setState(() => _isLoading = true);
    
    final success = await SystemSettingsUtil.setAutoStart(value);
    
    if (mounted) {
      setState(() {
        _autoStart = value;
        _isLoading = false;
      });
      
      if (value) {
        // 如果开启开机自启，显示提示
        _showAutoStartGuide();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('开机自启动已关闭'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 显示电池优化提示对话框
  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('建议设置'),
        content: const Text(
          '为了确保应用能在后台持续运行，建议将此应用添加到电池优化白名单。\n\n'
          '部分国产 ROM（如小米、华为、OPPO、vivo）可能需要在系统设置中手动允许后台运行和自启动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemSettingsUtil.openBatteryOptimizationSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 显示开机自启设置引导
  void _showAutoStartGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开机自启动已开启'),
        content: const Text(
          '开机自启动设置已保存。\n\n'
          '注意：部分国产 ROM（如小米、华为、OPPO、vivo）可能有额外的自启动管理，'
          '需要在系统设置 > 应用管理 > 自启动管理中手动开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // 打开应用设置页面
              SystemSettingsUtil.openBatteryOptimizationSettings();
            },
            child: const Text('查看设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: CircularProgressIndicator(),
          ),
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
                Icon(Icons.settings_applications, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '系统设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // 保留后台
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('保留后台运行'),
              subtitle: Text(
                _keepAlive 
                    ? '应用将在后台持续监控网络状态（屏幕常亮）' 
                    : '切换到后台时可能被系统休眠',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              value: _keepAlive,
              onChanged: _setKeepAlive,
              secondary: Icon(
                _keepAlive ? Icons.memory : Icons.memory_outlined,
                color: colorScheme.primary,
              ),
            ),

            const Divider(height: 8),

            // 开机自启
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开机自启动'),
              subtitle: Text(
                _autoStart 
                    ? '设备启动时自动运行本应用' 
                    : '需要手动打开应用',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              value: _autoStart,
              onChanged: _setAutoStart,
              secondary: Icon(
                _autoStart ? Icons.power_settings_new : Icons.power_off_outlined,
                color: _autoStart ? Colors.green : Colors.grey,
              ),
            ),
            
            // 提示信息
            if (_autoStart || _keepAlive)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '提示',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '部分国产 ROM（小米、华为、OPPO、vivo等）可能有额外的后台限制，'
                      '建议前往系统设置 > 应用管理 > 自启动管理中手动开启。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
