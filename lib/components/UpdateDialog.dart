import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:flutter/material.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onDismiss;
  @visibleForTesting
  final Future<bool> Function(UpdateInfo, Function(double))? downloadAndInstall;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onDismiss,
    this.downloadAndInstall,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _downloadFailed = false;
  double _progress = 0.0;

  Future<void> _handleUpdate() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadFailed = false;
      _progress = 0.0;
    });

    final success =
        await (widget.downloadAndInstall ?? UpdateUtil.downloadAndInstall)(
          widget.updateInfo,
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        );

    if (!mounted) return;
    if (success) {
      widget.onDismiss();
      return;
    }

    setState(() {
      _isDownloading = false;
      _downloadFailed = true;
    });
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
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.updateInfo.changelog,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_downloadFailed) ...[
                const SizedBox(height: 16),
                const Text('下载失败，请检查网络后重试，或在浏览器中手动下载。'),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                ),
                const SizedBox(height: 8),
                Text(
                  _progress == 0
                      ? '正在下载...'
                      : '下载中 ${(_progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.updateInfo.isForceUpdate && !_isDownloading)
          TextButton(onPressed: widget.onDismiss, child: const Text('稍后')),
        if (_downloadFailed && !_isDownloading)
          TextButton(
            onPressed: UpdateUtil.openReleasePage,
            child: const Text('浏览器下载'),
          ),
        FilledButton.icon(
          onPressed: _isDownloading ? null : _handleUpdate,
          icon: _isDownloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download),
          label: Text(
            _isDownloading
                ? '下载中...'
                : _downloadFailed
                ? '重试下载'
                : '立即更新',
          ),
        ),
      ],
    );
  }
}
