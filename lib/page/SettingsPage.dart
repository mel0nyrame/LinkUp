import 'package:flutter/material.dart';
import 'package:LinkUp/components/AccountCart.dart';
import 'package:LinkUp/components/NetWorkConfig.dart';
import 'package:LinkUp/components/SystemSettingsCard.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 用于触发刷新
  Key _refreshKey = UniqueKey();

  void _onConfigChanged() {
    // 配置改变时刷新页面
    setState(() {
      _refreshKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '认证设置',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '配置深澜认证参数',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // 账号信息卡片
          Accountcart(key: _refreshKey, onConfigChanged: _onConfigChanged),

          const SizedBox(height: 16),

          // 系统设置卡片（新增）
          const SystemSettingsCard(),

          const SizedBox(height: 16),

          // 网络配置卡片
          const NetworkConfigCard(),
        ],
      ),
    );
  }
}
