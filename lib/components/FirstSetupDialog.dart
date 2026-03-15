import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';

class FirstSetupDialog extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const FirstSetupDialog({
    super.key,
    required this.onSetupComplete,
  });

  @override
  State<FirstSetupDialog> createState() => _FirstSetupDialogState();
}

class _FirstSetupDialogState extends State<FirstSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _acidCtrl = TextEditingController(text: '1');
  bool _obscurePassword = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _acidCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final success = await ConfigUtil.saveConfig(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        acid: _acidCtrl.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isSaving = false);

      if (success) {
        widget.onSetupComplete();
        Navigator.of(context).pop();
      } else {
        setState(() {
          _errorMessage = '保存失败，请检查应用存储权限或重启应用后重试';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存失败，请检查应用存储权限'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '保存异常: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存异常: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        icon: const Icon(Icons.account_circle, size: 48, color: Color(0xFF1565C0)),
        title: const Text('首次配置'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '检测到首次使用，请配置校园网账号',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // 错误提示
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: '学号/工号',
                      hintText: '请输入用户名',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty == true ? '请输入用户名' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword 
                            ? Icons.visibility_outlined 
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => v?.isEmpty == true ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _acidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ACID (接入点)',
                      hintText: '默认: 1',
                      prefixIcon: Icon(Icons.place_outlined),
                      border: OutlineInputBorder(),
                      helperText: '常见值: 1, 2, 5, 11, 15',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => v?.isEmpty == true ? '请输入ACID' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveConfig,
              icon: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? '保存中...' : '保存并进入'),
            ),
          ),
        ],
      ),
    );
  }
}
