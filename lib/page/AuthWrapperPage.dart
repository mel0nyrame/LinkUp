import 'package:flutter/material.dart';
import 'package:LinkUp/components/FirstSetupDialog.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';

class AuthWrapperPage extends StatefulWidget {
  final Widget child;

  /// 权威的配置存在性检查，缺省走 [ConfigUtil.configExists]。
  ///
  /// 这层真实检查要读写配置文件，测试里换成一个可控的返回值，
  /// 首屏呈现的判定才能被确定性地验证。
  final Future<bool> Function()? configExists;

  const AuthWrapperPage({super.key, required this.child, this.configExists});

  @override
  State<AuthWrapperPage> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapperPage> {
  /// 首屏结论。
  ///
  /// null = 没有可信事实（既没有首帧可读的提示，真实检查也还没回来），此时维持
  /// 加载圈；加载圈不算首次实际内容，但它只出现在确实无法判定的窗口里。
  /// true = 已有配置，呈现 [AuthWrapperPage.child]；false = 需要首次配置。
  bool? _hasConfig;

  /// 首次配置对话框只弹一次。
  bool _setupDialogShown = false;

  @override
  void initState() {
    super.initState();
    // 偏好里的“配置存在”标记首帧就能同步读到，用它决定首帧呈现什么，别让加载圈
    // 占掉整个启动等待；它只是提示，权威事实由下面的真实检查给出。
    _hasConfig = SystemSettingsUtil.getAccountConfiguredHint();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    final check = widget.configExists ?? ConfigUtil.configExists;
    final exists = await check();
    if (!mounted) return;

    // 提示可能已经过期（例如配置文件被删），这里以真实检查为准纠正呈现。
    setState(() => _hasConfig = exists);

    if (!exists) {
      // 延迟一帧确保 MaterialApp 已初始化
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSetupDialog();
      });
    }
  }

  void _showSetupDialog() {
    if (_setupDialogShown || !mounted) return;
    _setupDialogShown = true;
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
    final hasConfig = _hasConfig;
    if (hasConfig == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!hasConfig) {
      // 等待配置完成，显示空白或 Logo
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
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
