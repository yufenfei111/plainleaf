import 'package:flutter/material.dart';

import '../../../../core/security/biometrics.dart';

/// 应用锁解锁页（W14）
///
/// 三要素齐全：
/// - 加载态：`_checking` 期间按钮转圈，但**不是常驻循环动画**
///   （常驻 ticker 会让 pumpAndSettle 永远等不到静止，整套 Widget 测试被拖死）；
/// - 错误态：密码不对就地显示，并清空输入框让用户直接重输，不必手动全选；
/// - 空态：还没输过密码时的引导文案。
///
/// 依赖全部从构造注入（校验函数、生物识别），不直接依赖 Provider：
/// 这一页要能被测试单独拉起来跑校验流程，而不是先搭一片 Riverpod 环境。
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    required this.verify,
    required this.onUnlocked,
    this.biometrics,
    this.biometricsAvailable = false,
  });

  /// 校验密码；由上层接到 AppLockService.verify
  final Future<bool> Function(String password) verify;

  /// 校验通过后回调（由上层翻转"已解锁"状态）
  final VoidCallback onUnlocked;

  final BiometricUnlock? biometrics;

  /// 是否显示生物识别入口（上层预先探过，避免点了必然失败）
  final bool biometricsAvailable;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await widget.verify(password);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) {
      setState(() {
        _error = '密码不正确';
        _controller.clear();
      });
      return;
    }
    widget.onUnlocked();
  }

  Future<void> _useBiometrics() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await (widget.biometrics ?? BiometricUnlock()).authenticate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text('素页已锁定', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('输入应用锁密码以继续', style: textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('lock-password-field'),
                  controller: _controller,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_checking,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('lock-submit'),
                    onPressed: _checking ? null : _submit,
                    child: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('解锁'),
                  ),
                ),
                if (widget.biometricsAvailable) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('lock-biometrics'),
                      onPressed: _checking ? null : _useBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('用指纹解锁'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('lock-error'),
                    style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
