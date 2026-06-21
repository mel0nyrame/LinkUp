import 'dart:async';
import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:LinkUp/main.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/page/SettingsPage.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';
import 'package:LinkUp/utils/AcidDetector.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isOnline = false;
  bool _shouldStopMonitor = false;
  RadUserInfo? _userInfo;
  String _currentAcid = '1';
  String _currentEnc = 'srun_bx1';

  final SrunClient client = SrunClient();
  Timer? _monitorTimer;
  Timer? _retryTimer;

  // 共享 AcidDetector — 跨 monitor / login cycle 复用，保留 _cachedPage
  // 和 _cachedPageUrl 缓存，避免每次 new 一个都丢失 portal HTML 缓存
  AcidDetector? _detector;

  AcidDetector _getDetector() {
    // 如果已创建但 baseUrl 过期（settings 改了 auth_server 但 monitor 还没
    // 通过 _restartMonitor 重新同步 client.host），重建 detector 让它跟随
    // 当前的 client.baseURL；否则用现有实例（保留 _cachedPage 缓存）
    if (_detector != null && _detector!.baseUrl != client.baseURL) {
      _detector!.reset();
      _detector = null;
    }
    return _detector ??= AcidDetector(baseUrl: client.baseURL);
  }

  // _userInfo 写入时间（用于 _doLogin 复用时校验 staleness，
  // 避免 monitor 几秒前缓存的 IP 与当前网络已切换的 IP 不一致）
  DateTime? _userInfoAt;

  // 5s 内的 _userInfo 视为 fresh 可复用；超过 5s 一律重新拉取 /rad_user_info
  // 防止用户切换网络 / DHCP 续约后 IP 已变而我们仍用旧 IP 登录
  static const Duration _userInfoMaxAge = Duration(seconds: 5);

  // _handleLogout 与 _manualLogin 互斥标志（专用，不与 _isLoading 混用；
  // _isLoading 是 UI spinner 状态，_userOperationInProgress 是 user-action 锁）
  bool _userOperationInProgress = false;

  // 检查间隔（秒）
  static const int checkInterval = 3;

  // 退避策略
  int _consecutiveFailures = 0;
  static const int maxBackoffSeconds = 60;

  @override
  void initState() {
    super.initState();

    // 页面加载后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });

    // 启动监控
    _startMonitor();
  }

  Future<void> _checkForUpdate() async {
    // 延迟 2 秒检查，避免启动时阻塞
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final updateInfo = await UpdateUtil.checkUpdate();

    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateInfo.isForceUpdate,
        builder: (context) => UpdateDialog(
          updateInfo: updateInfo,
          onDismiss: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  void dispose() {
    _shouldStopMonitor = true;
    _monitorTimer?.cancel();
    _retryTimer?.cancel();
    // 清掉 AcidDetector 内部 portal HTML 缓存，避免下次启动时拿到脏数据
    _detector?.reset();
    _detector = null;
    super.dispose();
  }

  // 启动网络监控
  void _startMonitor() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 先同步认证服务器地址，避免首次 _checkOnlineStatus 使用默认 host
      // 探测错误目标导致整轮监控用错地址
      await _syncHostFromConfig();

      if (_shouldStopMonitor || !mounted) return;

      // 立即执行一次检查
      _checkAndReconnect();

      // 定时检查（每3秒）
      _monitorTimer = Timer.periodic(
        const Duration(seconds: checkInterval),
        (_) => _checkAndReconnect(),
      );
    });
  }

  // 从本地配置同步认证服务器到 SrunClient
  Future<void> _syncHostFromConfig() async {
    try {
      final config = await ConfigUtil.loadConfig();
      if (config == null) return;
      final authServer = config['auth_server'] as String? ?? '10.129.1.1';
      if (client.host != authServer) {
        client.setHost(authServer);
        SrunLogin.client.setHost(authServer);
        LogUtil.info('监控启动前同步认证服务器: $authServer');
      }
    } catch (e) {
      LogUtil.warning('同步认证服务器失败: $e');
    }
  }

  // 重建监控定时器（注销/手动刷新路径）。
  // 先同步 host，避免用户在设置页改了 auth_server 后新 timer 还跑在旧 host 上；
  // 之后 cancel 旧 timer 再启新的，防止重叠触发。
  Future<void> _restartMonitor() async {
    await _syncHostFromConfig();
    if (_shouldStopMonitor || !mounted) return;
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => _checkAndReconnect(),
    );
  }

  // 检查连接状态并自动重连
  Future<void> _checkAndReconnect() async {
    if (_shouldStopMonitor) return;
    if (_isLoading) return; // 如果正在登录中，跳过

    // 检查是否已在线
    final isConnected = await _checkOnlineStatus();

    if (isConnected == true) {
      // 已在线，重置退避计数
      if (_consecutiveFailures > 0) {
        LogUtil.info('检测到在线状态，重置退避计数');
        _consecutiveFailures = 0;
      }
      if (!_isOnline) {
        // await 之后检查 mounted，避免 dispose race 触发 setState-after-dispose
        if (!mounted) return;
        setState(() {
          _isOnline = true;
          _statusMessage = '已在线';
        });
      }
      return;
    }

    if (isConnected == false) {
      // await 之后检查 mounted，避免 dispose race 触发 setState-after-dispose
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _statusMessage = '网络断开，正在自动重连...';
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _statusMessage = '网络检测失败，尝试连接...';
      });
    }

    // 执行安全登录
    await _safeLogin();
  }

  // 检查在线状态 - 使用 Reality 模式同时检测在线状态和 ACID
  Future<bool?> _checkOnlineStatus() async {
    try {
      LogUtil.info('检查在线状态...');
      
      // 使用 Reality 模式检测（同时检测在线状态和 ACID）
      final (detectedAcid, isOnline, err) = await _getDetector().reality(
        getAcid: true,
      );

      if (err != null) {
        LogUtil.error('Reality 检测失败', err);
        // Reality 失败时，尝试直接请求认证服务器看是否能通
        LogUtil.info('尝试直接请求认证服务器...');
      }

      LogUtil.info('Reality 检测结果: 在线=$isOnline, ACID=$detectedAcid, 错误=$err');

      // 仅在线时保存检测到的 ACID 到配置，避免离线时从错误 captive portal
      // 检测到错误 ACID 覆盖用户手动配置
      if (isOnline && detectedAcid != null && detectedAcid.isNotEmpty) {
        _currentAcid = detectedAcid;
        // 保存到配置
        final config = await ConfigUtil.loadConfig();
        if (config != null) {
          await ConfigUtil.saveConfig(
            username: config['username'] ?? '',
            password: config['password'] ?? '',
            acid: detectedAcid,
            autoAcid: config['auto_acid'] ?? true,
          );
          LogUtil.info('Reality 模式保存 ACID: $detectedAcid');
        }
      } else if (detectedAcid != null && detectedAcid.isNotEmpty) {
        // 离线时仅暂存到内存供本轮登录使用，不写入配置文件
        _currentAcid = detectedAcid;
        LogUtil.info('Reality 检测到 ACID（离线，仅内存暂存）: $detectedAcid');
      }

      if (isOnline) {
        // 已在线，获取用户信息
        try {
          final info = await client.getUserInfo();
          _userInfo = info;
          _userInfoAt = DateTime.now();
          LogUtil.info('在线状态: true, IP: ${info.onlineIp ?? "unknown"}');
        } catch (e) {
          LogUtil.warning('已在线但获取用户信息失败: $e');
        }
      }
      
      return isOnline;
    } catch (e, stackTrace) {
      LogUtil.error('检查在线状态失败', e, stackTrace);
      return null; // 返回 null 表示检测失败（网络问题），不是不在线
    }
  }

  // 安全登录（带异常捕获和退避策略）
  Future<void> _safeLogin() async {
    // 同时占用 _isLoading（UI spinner + monitor tick 跳过）和 _userOperationInProgress
    // （user-action 锁），确保 monitor-driven login 期间 _handleLogout / _manualLogin
    // 不会并发触发；finally 中清两个标志
    setState(() {
      _isLoading = true;
    });
    _userOperationInProgress = true;

    // 退避策略：连续失败越多，等待越久
    if (_consecutiveFailures > 0) {
      final backoffSeconds = (checkInterval * (1 << (_consecutiveFailures - 1)))
          .clamp(checkInterval, maxBackoffSeconds);
      LogUtil.info('退避等待 ${backoffSeconds}s（连续失败 $_consecutiveFailures 次）');
      await Future.delayed(Duration(seconds: backoffSeconds));
      if (_shouldStopMonitor || !mounted) {
        // 退出前清掉 _isLoading，避免后续 monitor tick 一直跳过
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    try {
      LogUtil.info('开始安全登录流程');
      await _doLogin();
      LogUtil.info('安全登录流程结束');
    } catch (e, stackTrace) {
      LogUtil.error('登录逻辑异常', e, stackTrace);
      if (mounted) {
        setState(() {
          _statusMessage = '登录异常: $e';
          _isLoading = false;
        });
      }
    } finally {
      // 释放 user-action 锁：让 _handleLogout / _manualLogin 后续可执行
      _userOperationInProgress = false;
    }

    // 根据结果更新退避计数
    if (_isOnline) {
      if (_consecutiveFailures > 0) {
        LogUtil.info('登录成功，重置退避计数（之前连续失败 $_consecutiveFailures 次）');
      }
      _consecutiveFailures = 0;
    } else {
      _consecutiveFailures++;
      LogUtil.info('登录未成功，连续失败 $_consecutiveFailures 次');
    }
  }

  // 执行登录
  Future<void> _doLogin() async {
    LogUtil.info('========== 开始执行登录 ==========');
    setState(() {
      _isLoading = true;
      _statusMessage = '正在检测网络状态...';
    });

    // 1. 检测 WiFi 是否开启
    bool isWifiConnected = false;
    for (int i = 0; i < 3; i++) {
      isWifiConnected = await NetworkUtil.isWifiConnected();
      LogUtil.info('WiFi 连接状态检测第${i + 1}次: $isWifiConnected');
      if (isWifiConnected) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    if (!isWifiConnected) {
      LogUtil.warning('WiFi 未连接，尝试直接请求认证服务器...');
    }

    setState(() {
      _statusMessage = '正在获取配置...';
    });

    // 2. 读取本地保存的配置
    LogUtil.info('正在读取本地配置...');
    final config = await ConfigUtil.loadConfig();
    if (config == null) {
      LogUtil.warning('未找到配置信息');
      setState(() {
        _isOnline = false;
        _statusMessage = '未找到配置信息';
        _isLoading = false;
      });
      return;
    }

    final String rawUsername = config['username'] ?? '';
    final String password = config['password'] ?? '';
    final String userType = config['user_type'] ?? '';
    String acid = config['acid'] ?? '1';
    _currentAcid = acid;
    final bool autoAcid = config['auto_acid'] ?? true;
    final String authServer = config['auth_server'] ?? '10.129.1.1';

    // 拼接用户名和运营商后缀
    final String username = userType.isNotEmpty ? '$rawUsername@$userType' : rawUsername;

    // 设置认证服务器地址（MainNavigator 实例 + SrunLogin 静态实例同步更新，
    // 避免 srucPortalLogin 内部使用 SrunLogin.client 时仍指向默认 host）
    if (client.host != authServer) {
      client.setHost(authServer);
      SrunLogin.client.setHost(authServer);
      LogUtil.info('认证服务器地址已设置为: $authServer');
    }

    LogUtil.info(
      '配置信息: username=$username, acid=$acid, autoAcid=$autoAcid, server=$authServer',
    );

    if (username.isEmpty || password.isEmpty) {
      LogUtil.warning('账号或密码为空，终止登录');
      setState(() {
        _isOnline = false;
        _statusMessage = '账号或密码为空';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取网络信息...');
    LogUtil.info('正在获取用户信息...');

    // 3. 获取 IP 和用户信息
    final String ip;
    try {
      // 复用 monitor tick 在线路径已经写入的 _userInfo（_checkOnlineStatus 内
      // 调用过 client.getUserInfo()），避免每个登录流程都重复请求一次 /rad_user_info
      // 但要校验 staleness：超过 _userInfoMaxAge 视为过期，强制重新拉取
      // （IP 可能在 DHCP 续约 / WiFi 切换后已变）。登录成功后的"必须再调
      // rad_user_info 确认"（CLAUDE.md §在线状态验证）在 line 464 的
      // newInfo = await client.getUserInfo() 仍会执行
      final RadUserInfo info;
      final userInfoFresh = _userInfo != null &&
          _userInfo!.isOnline &&
          _userInfoAt != null &&
          DateTime.now().difference(_userInfoAt!) < _userInfoMaxAge;
      if (userInfoFresh) {
        info = _userInfo!;
        LogUtil.info('复用 monitor tick 的 userInfo（IP=${info.clientIp ?? info.onlineIp}）');
      } else {
        info = await client.getUserInfo();
        _userInfo = info;
        _userInfoAt = DateTime.now();
      }
      // 优先使用 client_ip（始终存在），回退到 online_ip
      ip = (info.clientIp?.isNotEmpty == true ? info.clientIp : info.onlineIp) ?? '';
      LogUtil.info('获取到用户信息: clientIp=${info.clientIp}, onlineIp=${info.onlineIp}, 使用IP=$ip, 是否在线=${info.isOnline}');

      // 再次检查是否已经在线（可能在这期间已连接）
      if (info.isOnline) {
        LogUtil.info('用户已在线，跳过登录');
        setState(() {
          _isOnline = true;
          _statusMessage = '已在线';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      LogUtil.error('获取用户信息失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '无法连接认证服务器: $e';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取认证令牌...');
    LogUtil.info('正在获取 Challenge/Token...');

    // 4. 获取 Challenge/Token
    late final String token;
    try {
      final challenge = await client.getChallenge(username: username, ip: ip);
      token = challenge.challenge;
      LogUtil.info(
        '获取到 Token: ${token.substring(0, token.length > 10 ? 10 : token.length)}...',
      );
    } catch (e) {
      LogUtil.error('获取认证令牌失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '获取认证令牌失败: $e';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在登录...');

    // 5. 执行登录（自动尝试 ACID）
    LoginResult loginResult;

    try {
      if (autoAcid) {
        // 自动模式：先检测 ACID，如果检测失败则使用配置的 ACID
        LogUtil.info('使用自动 ACID 模式，开始检测 ACID...');
        final detector = _getDetector();
        // ACID 与 enc 检测是独立网络操作，并行跑能省一个 RTT 的 wall-clock；
        // 文档 §"ACID 自动探测策略" 没规定顺序
        final results = await Future.wait([
          _detectAcid(detector),
          detector.detectEnc(),
        ]);
        final detectedAcid = results[0];
        final detectedEnc = results[1];
        if (detectedAcid != null) {
          _currentAcid = detectedAcid;
          acid = detectedAcid;
          LogUtil.info('使用检测到的 ACID: $acid');
        } else {
          LogUtil.warning('ACID 检测失败，使用配置的 ACID: $acid');
        }
        if (detectedEnc != null && detectedEnc.isNotEmpty) {
          _currentEnc = detectedEnc;
          LogUtil.info('使用检测到的 enc: $_currentEnc');
        } else {
          LogUtil.warning('enc 检测失败，使用默认值: $_currentEnc');
        }

        setState(() {
          _statusMessage = '正在使用 ACID: $acid 登录...';
        });
        loginResult = await SrunLogin.srucPortalLogin(
          username,
          password,
          acid,
          token,
          ip,
          encVer: _currentEnc,
        );
      } else {
        // 手动模式：使用配置的 ACID
        _currentAcid = acid;
        LogUtil.info('使用手动 ACID 模式: acid=$acid');
        setState(() {
          _statusMessage = '正在使用 ACID: $acid 登录...';
        });
        loginResult = await SrunLogin.srucPortalLogin(
          username,
          password,
          acid,
          token,
          ip,
          encVer: _currentEnc,
        );
      }
    } catch (e) {
      LogUtil.error('登录请求失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '登录请求失败: $e';
        _isLoading = false;
      });
      return;
    }

    // 6. 检查登录结果
    if (!loginResult.success) {
      LogUtil.warning(
        '登录失败: ${loginResult.message}, 错误类型: ${loginResult.errorType}',
      );
      setState(() {
        _isOnline = false;
        _statusMessage = '登录失败: ${loginResult.message}';
        _isLoading = false;
      });
      return;
    }

    // 7. 登录成功，刷新用户信息并验证在线状态
    // CLAUDE.md §在线状态验证：srun_portal 返回 error: "ok" 不代表真正在线，
    // 必须再次调用 rad_user_info 确认
    LogUtil.info('登录成功，正在验证在线状态...');
    final newInfo = await client.getUserInfo();

    if (!newInfo.isOnline) {
      // srun_portal 返回成功但 rad_user_info 显示不在线 — 服务器端可能未真正授权
      LogUtil.warning('登录后验证失败：rad_user_info 返回不在线，srun_portal 结果不可靠');
      setState(() {
        _isOnline = false;
        _statusMessage = '登录验证失败，将自动重试';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isOnline = true;
      _userInfo = newInfo;
      // 同步刷新 _userInfoAt 时间戳，确保 5s staleness 校验对最新 userInfo 有效
      _userInfoAt = DateTime.now();
      _statusMessage = '登录成功';
      _isLoading = false;
    });
    LogUtil.info('登录流程完成，用户已在线，IP: ${newInfo.onlineIp ?? "unknown"}');

    // 显示成功提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('校园网已连接'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
    LogUtil.info('========== 登录流程结束 ==========');
  }

  // 使用 AcidDetector 自动检测 ACID（使用缓存的 detector）
  Future<String?> _detectAcid(AcidDetector detector) async {
    LogUtil.info('[MainNavigation] 开始自动检测 ACID...');

    setState(() {
      _statusMessage = '正在自动检测网络接入点...';
    });

    try {
      final acid = await detector.detectAcid();
      
      if (acid != null && acid.isNotEmpty) {
        LogUtil.info('[MainNavigation] 自动检测 ACID 成功: $acid');
        
        // 保存检测到的 ACID 到配置
        final config = await ConfigUtil.loadConfig();
        if (config != null) {
          await ConfigUtil.saveConfig(
            username: config['username'] ?? '',
            password: config['password'] ?? '',
            acid: acid,
            autoAcid: config['auto_acid'] ?? true,
          );
          LogUtil.info('[MainNavigation] 已保存检测到的 ACID: $acid');
        }
        
        return acid;
      } else {
        LogUtil.warning('[MainNavigation] 自动检测 ACID 失败，将使用配置的 ACID');
        return null;
      }
    } catch (e, stackTrace) {
      LogUtil.error('[MainNavigation] 检测 ACID 过程出错', e, stackTrace);
      return null;
    }
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? MyApp.iosBlue.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? MyApp.iosBlue : const Color(0xFF8E8E93),
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? MyApp.iosBlue : const Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 注销 — 使用 DM API (/cgi-bin/rad_user_dm)，与登录加密链无关
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认注销'),
        content: const Text('确定要注销校园网连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: MyApp.iosRed),
            child: const Text('注销'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 与 _manualLogin 互斥：用专用 _userOperationInProgress 锁（不用 _isLoading
    // 因为 _isLoading 是 UI 标志，且 monitor tick 中也会被反复翻转）
    if (_userOperationInProgress) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在处理中，请稍候再试')),
        );
      }
      return;
    }
    _userOperationInProgress = true;

    _monitorTimer?.cancel();
    setState(() {
      _isLoading = true;
      _statusMessage = '正在注销...';
    });

    // 显式重建控制：成功 / 失败 / 异常路径都重建 monitor；config==null 早退不重建
    // （避免每 3s 死循环调 _doLogin → '未找到配置信息'）。把 restart 调用从 finally
    // 移出来，避免与 try 块共享一个 shouldRestartMonitor flag
    try {
      final config = await ConfigUtil.loadConfig();
      if (config == null) {
        // 配置丢失：清掉 loading 状态，UI 不能卡在 spinner；不 restart monitor
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = '未找到配置，无法注销';
          });
        }
        return;
      }

      final rawUsername = config['username'] ?? '';
      final userType = config['user_type'] ?? '';
      final username = userType.isNotEmpty ? '$rawUsername@$userType' : rawUsername;

      // 获取当前 IP
      final info = await client.getUserInfo();
      final ip = (info.clientIp?.isNotEmpty == true ? info.clientIp : info.onlineIp) ?? '';

      // DM 注销：只需要 username + ip + 时间戳签名，不需要 token/加密
      final success = await SrunLogin.dmLogout(username: username, ip: ip);

      if (mounted) {
        setState(() {
          _isOnline = false;
          _userInfo = null;
          _userInfoAt = null;
          _isLoading = false;
          _statusMessage = success ? '已注销' : '注销失败';
          _consecutiveFailures = 0;
        });
        // 清掉 AcidDetector 缓存的 portal HTML 和 URL，避免下次登录复用
        // 跨 portal session / 跨校区的旧 _cachedPage / _cachedPageUrl
        // 设为 null 而非仅 reset：让下次 _getDetector() 重建新实例，
        // 避免旧 in-flight reality() 完成时通过旧 ref 写脏新 cache
        _detector?.reset();
        _detector = null;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '已成功注销' : '注销失败，请重试'),
            backgroundColor: success ? MyApp.iosGreen : MyApp.iosRed,
          ),
        );
      }
      // 成功路径：重建 monitor
      if (mounted) {
        await _restartMonitor();
      }
    } catch (e, stackTrace) {
      LogUtil.error('注销异常', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '注销异常';
        });
        // 异常路径不 restart monitor：
        // 配置文件损坏（loadConfig 抛 FileSystemException）时，restart monitor
        // 会让 monitor tick 立即重试 _doLogin → loadConfig 再抛 → 死循环 + 日志刷屏
        // 让用户主动冷启动 app 或修好配置后重启 monitor 即可
      }
    } finally {
      // 释放 user-action 锁（无论成功 / 失败 / 早退），让 _manualLogin 后续可执行
      _userOperationInProgress = false;
    }
  }

  // 手动触发登录（下拉刷新）
  Future<void> _manualLogin() async {
    LogUtil.info('用户手动触发登录（下拉刷新）');
    // 与 _handleLogout 互斥：用专用 _userOperationInProgress 锁
    if (_userOperationInProgress) {
      LogUtil.info('已有登录/注销流程在进行，跳过本次手动登录');
      return;
    }
    _userOperationInProgress = true;
    _consecutiveFailures = 0;
    _monitorTimer?.cancel();
    await _safeLogin();
    // 走 _restartMonitor 同步 host，避免用户改了 auth_server 后新 timer 用旧 host
    await _restartMonitor();
    // 释放 user-action 锁
    _userOperationInProgress = false;
    LogUtil.info('手动登录完成，监控已恢复');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        actions: [
          if (_isOnline)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('注销'),
                style: TextButton.styleFrom(
                  foregroundColor: MyApp.iosRed,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              OverviewPage(
                isLoading: _isLoading,
                statusMessage: _statusMessage,
                isOnline: _isOnline,
                currentAcid: _currentAcid,
                userInfo: _userInfo,
                onRefresh: () => _manualLogin(),
              ),
              const SettingsPage(),
            ],
          ),
          // Floating liquid glass pill — transparent background, no Scaffold chrome
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                child: LiquidGlass.withOwnLayer(
                  settings: const LiquidGlassSettings(
                    blur: 18,
                    thickness: 10,
                    glassColor: Color(0x1AFFFFFF),
                    saturation: 1.05,
                  ),
                  shape: LiquidRoundedSuperellipse(borderRadius: 28),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNavItem(
                          index: 0,
                          icon: Icons.speed_outlined,
                          selectedIcon: Icons.speed,
                          label: '概况',
                        ),
                        _buildNavItem(
                          index: 1,
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          label: '设置',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
