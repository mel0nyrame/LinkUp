import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:LinkUp/utils/LogUtil.dart';

class WindowsLogsPage extends StatefulWidget {
  const WindowsLogsPage({super.key, this.readLog, this.clearLogs});

  final Future<String> Function()? readLog;
  final Future<void> Function()? clearLogs;

  @override
  State<WindowsLogsPage> createState() => _WindowsLogsPageState();
}

class _WindowsLogsPageState extends State<WindowsLogsPage> {
  String? _logContent;
  bool _isLoading = false;
  bool _loadFailed = false;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogs());
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
      _logContent = null;
    });

    try {
      final content = await (widget.readLog ?? LogUtil.readLogOrThrow)();
      if (!mounted) return;
      setState(() {
        _logContent = content;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _copyLogs() async {
    final content = _logContent;
    if (content == null || content.isEmpty || _isLoading) return;

    try {
      await Clipboard.setData(ClipboardData(text: content));
      _showFeedback('日志已复制到剪贴板');
    } catch (_) {
      _showFeedback('复制日志失败，请重试');
    }
  }

  Future<void> _confirmClearLogs() async {
    if (_logContent == null || _logContent!.isEmpty || _isClearing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空日志'),
        content: const Text('确定要清空所有诊断日志吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('清空日志'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      await (widget.clearLogs ?? LogUtil.clearOrThrow)();
      if (!mounted) return;
      setState(() {
        _logContent = '';
        _isClearing = false;
      });
      _showFeedback('日志已清空');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isClearing = false);
      _showFeedback('清空日志失败，请重试');
    }
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logContent = _logContent;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('诊断日志', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                '查看、复制或清空本机保存的应用运行记录。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.article_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '应用日志',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: '重新读取',
                              onPressed: _isLoading ? null : _loadLogs,
                              icon: const Icon(Icons.refresh),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed:
                                  logContent == null ||
                                      logContent.isEmpty ||
                                      _isLoading
                                  ? null
                                  : _copyLogs,
                              icon: const Icon(Icons.copy_outlined),
                              label: const Text('复制'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed:
                                  logContent == null ||
                                      logContent.isEmpty ||
                                      _isLoading ||
                                      _isClearing
                                  ? null
                                  : _confirmClearLogs,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('清空'),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Expanded(child: _buildLogContent(context, logContent)),
                        const SizedBox(height: 10),
                        Text(
                          _statusText(logContent),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogContent(BuildContext context, String? logContent) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            const Text('读取日志失败'),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (logContent == null || logContent.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('日志文件为空'),
            const SizedBox(height: 4),
            Text(
              '暂无日志记录',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: SelectableText(
        logContent,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontFamily: 'monospace', height: 1.5),
      ),
    );
  }

  String _statusText(String? logContent) {
    if (_isLoading) return '正在读取日志…';
    if (_loadFailed) return '日志内容暂不可用';
    if (logContent == null || logContent.isEmpty) return '0 行';
    return '共 ${logContent.split('\n').length} 行';
  }
}
