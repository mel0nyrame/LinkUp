import 'package:flutter/material.dart';
import 'package:LinkUp/components/GlassCard.dart';
import 'package:LinkUp/components/InfoDataRow.dart';
import 'package:LinkUp/components/InfoCard.dart';
import 'package:LinkUp/components/StatusCard.dart';
import 'package:LinkUp/main.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';

class OverviewPage extends StatefulWidget {
  final bool isLoading;
  final String? statusMessage;
  final bool isOnline;
  final String? currentAcid;
  final RadUserInfo? userInfo;
  final VoidCallback? onRefresh;

  const OverviewPage({
    super.key,
    this.isLoading = false,
    this.statusMessage,
    this.isOnline = false,
    this.currentAcid,
    this.userInfo,
    this.onRefresh,
  });

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  String? _getStatusText() {
    if (widget.isOnline) return '已连接';
    if (widget.statusMessage != null) {
      if (widget.statusMessage!.contains('WiFi未开启')) return 'WiFi未开启';
      if (widget.statusMessage!.contains('未找到配置')) return '未配置';
      if (widget.statusMessage!.contains('账号或密码为空')) return '配置不完整';
      return '未连接';
    }
    return null;
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.bitLength ~/ 10);
    if (i >= suffixes.length) i = suffixes.length - 1;
    final size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  String _formatTimestamp(int? ts) {
    if (ts == null || ts <= 0) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int? s) {
    if (s == null || s <= 0) return '-';
    final days = s ~/ 86400;
    final hrs = (s % 86400) ~/ 3600;
    final mins = (s % 3600) ~/ 60;
    if (days > 0) return '${days}天${hrs}小时${mins}分';
    if (hrs > 0) return '${hrs}小时${mins}分';
    return '${mins}分钟';
  }

  @override
  Widget build(BuildContext context) {
    final userInfo = widget.userInfo;
    final online = widget.isOnline;

    String? detailText;
    if (widget.isLoading && widget.currentAcid != null) {
      detailText = '正在尝试 ACID: ${widget.currentAcid}';
    } else if (widget.statusMessage != null) {
      detailText = widget.statusMessage;
    }

    return RefreshIndicator(
      color: MyApp.iosBlue,
      onRefresh: () async {
        widget.onRefresh?.call();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Large title header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'LinkUp',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                online ? '网络已连接' : '网络监控中',
                style: TextStyle(
                  fontSize: 15,
                  color: online ? MyApp.iosGreen : MyApp.iosSecondaryText,
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Status card
                Statuscard(
                  isOnline: online,
                  statusText: _getStatusText(),
                  detailText: detailText,
                  errorMsg: online ? null : widget.statusMessage,
                ),

                const SizedBox(height: 16),

                // Loading indicator
                if (widget.isLoading)
                  GlassCard(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MyApp.iosBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.statusMessage ?? '正在连接...',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error card
                if (!widget.isLoading && !online && widget.statusMessage != null)
                  GlassCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: MyApp.iosRed, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.statusMessage!,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (widget.isLoading || (!online && widget.statusMessage != null))
                  const SizedBox(height: 16),

                // Device card
                if (userInfo != null && userInfo.isOnline)
                  _buildDeviceCard(userInfo)
                else
                  const InfoCard(
                    icon: Icons.devices,
                    title: '在线设备',
                    children: [],
                  ),

                const SizedBox(height: 16),

                // Network info
                if (userInfo != null && userInfo.isOnline)
                  InfoCard(
                    icon: Icons.wifi,
                    title: '网络信息',
                    children: [
                      InfoDataRow(
                          label: 'IP 地址',
                          value: userInfo.onlineIp,
                          icon: Icons.laptop_mac),
                      InfoDataRow(
                          label: 'IPv6',
                          value: userInfo.onlineIp6,
                          icon: Icons.lan_outlined),
                      InfoDataRow(
                          label: 'MAC',
                          value: userInfo.userMac,
                          icon: Icons.fingerprint),
                    ],
                  )
                else
                  const InfoCard(
                    icon: Icons.wifi,
                    title: '网络信息',
                    children: [],
                  ),

                const SizedBox(height: 16),

                // Traffic
                if (userInfo != null && userInfo.isOnline)
                  InfoCard(
                    icon: Icons.insert_chart_outlined,
                    title: '流量统计',
                    children: [
                      InfoDataRow(
                          label: '本次会话',
                          value: _formatBytes(userInfo.allBytes),
                          icon: Icons.arrow_circle_down,
                          valueColor: MyApp.iosBlue),
                      InfoDataRow(
                          label: '累计流量',
                          value: _formatBytes(userInfo.sumBytes),
                          icon: Icons.layers,
                          valueColor: const Color(0xFFAF52DE)),
                      InfoDataRow(
                          label: '剩余流量',
                          value: _formatBytes(userInfo.remainBytes),
                          icon: Icons.pie_chart,
                          valueColor: MyApp.iosGreen),
                    ],
                  )
                else
                  const InfoCard(
                    icon: Icons.insert_chart_outlined,
                    title: '流量统计',
                    children: [],
                  ),

                const SizedBox(height: 16),

                // Time
                if (userInfo != null && userInfo.isOnline)
                  InfoCard(
                    icon: Icons.timer,
                    title: '在线时长',
                    children: [
                      InfoDataRow(
                          label: '本次登录',
                          value: _formatTimestamp(userInfo.addTime),
                          icon: Icons.login),
                      InfoDataRow(
                          label: '累计在线',
                          value: _formatDuration(userInfo.sumSeconds),
                          icon: Icons.hourglass_bottom),
                      InfoDataRow(
                          label: '剩余时长',
                          value: userInfo.remainSeconds == null ||
                                  userInfo.remainSeconds == 0
                              ? '无限制'
                              : _formatDuration(userInfo.remainSeconds),
                          icon: Icons.timelapse),
                    ],
                  )
                else
                  const InfoCard(
                    icon: Icons.timer,
                    title: '在线时长',
                    children: [],
                  ),

                const SizedBox(height: 16),

                // Account + Finance combined
                if (userInfo != null && userInfo.isOnline)
                  InfoCard(
                    icon: Icons.account_circle,
                    title: '账户',
                    children: [
                      InfoDataRow(
                          label: '用户名',
                          value: userInfo.userName,
                          icon: Icons.person),
                      InfoDataRow(
                          label: '套餐',
                          value: userInfo.productsName,
                          icon: Icons.card_giftcard),
                      InfoDataRow(
                          label: '余额',
                          value: '¥${userInfo.userBalance}',
                          icon: Icons.credit_card,
                          valueColor: MyApp.iosGreen),
                    ],
                  )
                else
                  const InfoCard(
                    icon: Icons.account_circle,
                    title: '账户',
                    children: [],
                  ),

                const SizedBox(height: 32),
                // Space for floating pill nav
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(RadUserInfo info) {
    final devices = info.onlineDeviceDetail?.values.toList() ?? [];

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: MyApp.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.devices, color: MyApp.iosBlue, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '在线设备',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: MyApp.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${info.onlineDeviceTotal} 台',
                  style: const TextStyle(
                    color: MyApp.iosBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('暂无设备', style: TextStyle(color: Color(0xFF8E8E93))),
            )
          else ...[
            const SizedBox(height: 12),
            Divider(color: Colors.black.withOpacity(0.06), height: 1),
            ...devices.asMap().entries.map((e) {
              final d = e.value;
              final (icon, bgColor, iconColor) = _deviceIconAndColor(d.osName);
              return Padding(
                padding: EdgeInsets.only(top: e.key == 0 ? 8 : 6, bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(icon, color: iconColor, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.osName ?? 'Unknown',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            d.ip ?? '-',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (d.className?.split('/').first ?? '-'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// 返回 (图标, 背景色, 图标色) 三元组
  (IconData, Color, Color) _deviceIconAndColor(String? osName) {
    if (osName == null) return (Icons.devices_other, Colors.grey.shade200, Colors.grey);
    final os = osName.toLowerCase();
    if (os.contains('iphone') || os.contains('ios ')) {
      return (Icons.phone_iphone, Colors.black.withOpacity(0.8), Colors.white);
    }
    if (os.contains('ipad')) {
      return (Icons.tablet_mac, Colors.black.withOpacity(0.8), Colors.white);
    }
    if (os.contains('mac')) {
      return (Icons.laptop_mac, Colors.black.withOpacity(0.8), Colors.white);
    }
    if (os.contains('android')) {
      return (Icons.phone_android, MyApp.iosGreen.withOpacity(0.15), MyApp.iosGreen);
    }
    if (os.contains('windows')) {
      return (Icons.laptop_windows, const Color(0xFF0078D4).withOpacity(0.15), const Color(0xFF0078D4));
    }
    if (os.contains('linux')) {
      return (Icons.terminal, Colors.orange.withOpacity(0.15), Colors.orange);
    }
    return (Icons.devices_other, Colors.grey.shade200, Colors.grey);
  }
}
