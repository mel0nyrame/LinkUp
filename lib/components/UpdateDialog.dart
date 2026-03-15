import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:flutter/material.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onDismiss;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onDismiss,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  Future<void> _handleUpdate() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    final success = await UpdateUtil.downloadAndInstall(
      widget.updateInfo.downloadUrl,
      (progress) {
        setState(() => _progress = progress);
      },
    );

    if (!success && mounted) {
      // 下载失败，提供浏览器跳转选项
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('下载失败'),
          content: const Text('是否跳转到浏览器手动下载？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                UpdateUtil.openReleasePage();
              },
              child: const Text('跳转'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.system_update,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text('发现新版本 ${widget.updateInfo.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '更新内容：',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.updateInfo.changelog,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  '下载中 ${(_progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.updateInfo.isForceUpdate && !_isDownloading)
          TextButton(
            onPressed: widget.onDismiss,
            child: const Text('稍后'),
          ),
        FilledButton.icon(
          onPressed: _isDownloading ? null : _handleUpdate,
          icon: _isDownloading 
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download),
          label: Text(_isDownloading ? '下载中...' : '立即更新'),
        ),
      ],
    );
  }
}
