import 'package:flutter/material.dart';
import 'package:LinkUp/components/InfoDataRow.dart';
import 'package:LinkUp/components/DeviceInfoRow.dart';
import 'package:LinkUp/components/InformationCart.dart';
import 'package:LinkUp/components/StatusCard.dart';
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
  // 获取状态卡片显示的文本
  String? _getStatusText() {
    if (widget.isOnline) return '在线';
    if (widget.statusMessage != null) {
      if (widget.statusMessage!.contains('WiFi未开启')) return 'WiFi未开启';
      if (widget.statusMessage!.contains('未找到配置')) return '未配置';
      if (widget.statusMessage!.contains('账号或密码为空')) return '配置不完整';
      return '离线';
    }
    return null;
  }

  // 格式化字节
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.bitLength ~/ 10);
    if (i >= suffixes.length) i = suffixes.length - 1;
    final size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  // 格式化时间戳
  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return '-';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // 格式化时长
  String _formatDuration(int seconds) {
    if (seconds <= 0) return '-';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}天${hours}小时${mins}分';
    if (hours > 0) return '${hours}小时${mins}分';
    return '${mins}分钟';
  }

  @override
  Widget build(BuildContext context) {
    final String? statusText = _getStatusText();
    final bool showAsOnline = widget.isOnline;
    final userInfo = widget.userInfo;
    final colorScheme = Theme.of(context).colorScheme;

    String? detailText;
    if (widget.isLoading && widget.currentAcid != null) {
      detailText = '正在尝试 ACID: ${widget.currentAcid}';
    } else if (widget.statusMessage != null) {
      detailText = widget.statusMessage;
    }

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh?.call();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态卡片
                  Statuscard(
                    isOnline: showAsOnline,
                    statusText: statusText,
                    detailText: detailText,
                    errorMsg: widget.isOnline ? null : widget.statusMessage,
                  ),

                  const SizedBox(height: 16),

                  // 加载状态指示器
                  if (widget.isLoading)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.statusMessage ?? '正在连接...',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 错误提示
                  if (!widget.isLoading &&
                      !widget.isOnline &&
                      widget.statusMessage != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.statusMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (widget.isLoading ||
                      (widget.statusMessage != null && !widget.isOnline))
                    const SizedBox(height: 16),

                  // 账户信息卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.account_circle,
                      title: '账户信息',
                      children: [
                        InfoDataRow(
                          label: '用户名',
                          value: userInfo.userName,
                          icon: Icons.person,
                        ),
                        InfoDataRow(
                          label: '真实姓名',
                          value: userInfo.realName.isEmpty
                              ? '-'
                              : userInfo.realName,
                          icon: Icons.badge,
                        ),
                        InfoDataRow(
                          label: '用户组ID',
                          value: userInfo.groupId,
                          icon: Icons.group,
                        ),
                        InfoDataRow(
                          label: '套餐名称',
                          value: userInfo.productsName,
                          icon: Icons.card_membership,
                        ),
                        InfoDataRow(
                          label: '计费套餐',
                          value: userInfo.billingName,
                          icon: Icons.payment,
                        ),
                        InfoDataRow(
                          label: '产品ID',
                          value: userInfo.productsId,
                          icon: Icons.label,
                        ),
                        InfoDataRow(
                          label: '套餐ID',
                          value: userInfo.packageId,
                          icon: Icons.inventory,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.account_circle,
                      title: '账户信息',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 网络信息卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.network_check,
                      title: '网络信息',
                      children: [
                        InfoDataRow(
                          label: '当前IP',
                          value: userInfo.onlineIp,
                          icon: Icons.computer,
                        ),
                        InfoDataRow(
                          label: 'IPv6',
                          value: userInfo.onlineIp6,
                          icon: Icons.settings_ethernet,
                        ),
                        InfoDataRow(
                          label: 'MAC地址',
                          value: userInfo.userMac,
                          icon: Icons.memory,
                        ),
                        InfoDataRow(
                          label: '域名',
                          value: userInfo.domain.isEmpty
                              ? '-'
                              : userInfo.domain,
                          icon: Icons.language,
                        ),
                        InfoDataRow(
                          label: 'PPPoE拨号',
                          value: userInfo.pppoeDial == '1' ? '支持' : '不支持',
                          icon: Icons.dialer_sip,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.network_check,
                      title: '网络信息',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 流量统计卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.data_usage,
                      title: '流量统计',
                      children: [
                        InfoDataRow(
                          label: '本次会话流量',
                          value: _formatBytes(userInfo.allBytes),
                          icon: Icons.download,
                          valueColor: Colors.blue,
                        ),
                        InfoDataRow(
                          label: '历史累计流量',
                          value: _formatBytes(userInfo.sumBytes),
                          icon: Icons.history,
                          valueColor: Colors.purple,
                        ),
                        InfoDataRow(
                          label: '剩余流量',
                          value: _formatBytes(userInfo.remainBytes),
                          icon: Icons.storage,
                          valueColor: Colors.orange,
                        ),
                        InfoDataRow(
                          label: '入口流量',
                          value: _formatBytes(userInfo.bytesIn),
                          icon: Icons.arrow_downward,
                        ),
                        InfoDataRow(
                          label: '出口流量',
                          value: _formatBytes(userInfo.bytesOut),
                          icon: Icons.arrow_upward,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.data_usage,
                      title: '流量统计',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 在线时长卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.timer,
                      title: '在线时长',
                      children: [
                        InfoDataRow(
                          label: '本次登录时间',
                          value: _formatTimestamp(userInfo.addTime),
                          icon: Icons.login,
                        ),
                        InfoDataRow(
                          label: '最后心跳时间',
                          value: _formatTimestamp(userInfo.keepaliveTime),
                          icon: Icons.favorite,
                        ),
                        InfoDataRow(
                          label: '累计在线时长',
                          value: _formatDuration(userInfo.sumSeconds),
                          icon: Icons.schedule,
                        ),
                        InfoDataRow(
                          label: '剩余时长',
                          value: userInfo.remainSeconds == 0
                              ? '无限制'
                              : _formatDuration(userInfo.remainSeconds),
                          icon: Icons.hourglass_empty,
                        ),
                        InfoDataRow(
                          label: '结账日期',
                          value: userInfo.checkoutDate == 0
                              ? '-'
                              : _formatTimestamp(userInfo.checkoutDate),
                          icon: Icons.event,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.timer,
                      title: '在线时长',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 财务信息卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.account_balance_wallet,
                      title: '财务信息',
                      children: [
                        InfoDataRow(
                          label: '账户余额',
                          value: '¥${userInfo.userBalance}',
                          icon: Icons.account_balance,
                          valueColor: Colors.green,
                        ),
                        InfoDataRow(
                          label: '钱包余额',
                          value: '¥${userInfo.walletBalance}',
                          icon: Icons.wallet,
                          valueColor: Colors.blue,
                        ),
                        InfoDataRow(
                          label: '用户费用',
                          value: '¥${userInfo.userCharge}',
                          icon: Icons.money_off,
                          valueColor: Colors.red,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.account_balance_wallet,
                      title: '财务信息',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 在线设备详情卡片
                  if (userInfo != null && userInfo.isOnline)
                    _buildDeviceCard(context, userInfo)
                  else
                    SectionCard(
                      icon: Icons.devices,
                      title: '在线设备详情',
                      children: const [],
                    ),

                  const SizedBox(height: 16),

                  // 系统版本卡片
                  if (userInfo != null && userInfo.isOnline)
                    SectionCard(
                      icon: Icons.system_update,
                      title: '系统版本',
                      children: [
                        InfoDataRow(
                          label: '系统版本',
                          value: userInfo.sysver,
                          icon: Icons.info,
                        ),
                        InfoDataRow(
                          label: 'ServerFlag',
                          value: userInfo.serverFlag.toString(),
                          icon: Icons.flag,
                        ),
                      ],
                    )
                  else
                    SectionCard(
                      icon: Icons.system_update,
                      title: '系统版本',
                      children: const [],
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建设备卡片
  Widget _buildDeviceCard(BuildContext context, RadUserInfo userInfo) {
    final colorScheme = Theme.of(context).colorScheme;
    final devices = userInfo.onlineDeviceDetail?.values.toList() ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '在线设备详情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${userInfo.onlineDeviceTotal} 台',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (devices.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('暂无设备信息'),
                ),
              )
            else
              ...devices.asMap().entries.map((entry) {
                final index = entry.key;
                final device = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            device.osName.contains('iPhone') ||
                                    device.osName.contains('Mac')
                                ? Icons.apple
                                : Icons.android,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '设备 ${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              device.className.split('/').first,
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DeviceInfoRow(label: '系统', value: device.osName),
                      DeviceInfoRow(label: 'IP地址', value: device.ip),
                      DeviceInfoRow(label: 'IPv6', value: device.ip6),
                      DeviceInfoRow(label: '设备ID', value: device.radOnlineId),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
