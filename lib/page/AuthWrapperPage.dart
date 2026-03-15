import 'package:flutter/material.dart';
import 'package:LinkUp/components/FirstSetupDialog.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';

class AuthWrapperPage extends StatefulWidget {
  final Widget child;

  const AuthWrapperPage({
    super.key,
    required this.child,
  });

  @override
  State<AuthWrapperPage> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapperPage> {
  bool _isLoading = true;
  bool _hasConfig = false;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    final exists = await ConfigUtil.configExists();
    setState(() {
      _hasConfig = exists;
      _isLoading = false;
    });

    if (!exists) {
      // 延迟一帧确保 MaterialApp 已初始化
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSetupDialog();
      });
    }
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FirstSetupDialog(
        onSetupComplete: () {
          setState(() => _hasConfig = true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasConfig) {
      // 等待配置完成，显示空白或 Logo
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('LinkUp', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('首次启动配置中...', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
