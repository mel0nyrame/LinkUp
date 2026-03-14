// Powered By Kimi
// 这真不会写
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NetworkConfigCard extends StatefulWidget {
  const NetworkConfigCard({super.key});

  @override
  State<NetworkConfigCard> createState() => _NetworkConfigCardState();
}

class _NetworkConfigCardState extends State<NetworkConfigCard> {
  bool _autoAcid = true;
  final _acidCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _acidCtrl.dispose();
    super.dispose();
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
                    ? '系统将根据网络环境自动选择接入点' 
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
                        '自动',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
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
              });
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
}
