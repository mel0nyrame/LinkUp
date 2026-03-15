import 'package:flutter/material.dart';

class Statuscard extends StatelessWidget {
  final bool isOnline;
  final String? statusText;
  final String? detailText;  // 详细状态，如"正在尝试 ACID: 1"
  final String? errorMsg;
  final String? serverFlag;

  const Statuscard({
    super.key,
    this.isOnline = false,
    this.statusText,
    this.detailText,
    this.errorMsg,
    this.serverFlag,
  });

  @override
  Widget build(BuildContext context) {
    // 根据在线状态设置颜色
    final Color statusColor = isOnline ? Colors.green : Colors.red;
    final Color bgColor = isOnline ? Colors.green.shade50 : Colors.red.shade50;
    final String displayText = isOnline ? (statusText ?? '在线') : (statusText ?? '离线');

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.5),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 显示详细状态（如"正在尝试 ACID: 1"）
            if (detailText != null && detailText!.isNotEmpty)
              Text(
                detailText!,
                style: TextStyle(
                  color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (errorMsg != null && errorMsg!.isNotEmpty)
              Text(
                errorMsg!,
                style: TextStyle(
                  color: isOnline ? Colors.green.shade600 : Colors.red.shade600,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              )
            else
              Text(
                'error: ',
                style: TextStyle(
                  color: isOnline ? Colors.green.shade600 : Colors.red.shade600,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            const SizedBox(height: 4),
            Text(
              serverFlag != null && serverFlag!.isNotEmpty 
                  ? 'ServerFlag: $serverFlag' 
                  : 'ServerFlag: ',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
