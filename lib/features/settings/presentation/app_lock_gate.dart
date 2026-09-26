import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/biometrics.dart';
import 'lock_screen.dart';
import 'providers/security_providers.dart';

/// 应用锁门控（W14）
///
/// 包在路由树外面：应用锁开着且当前未验证 → 只画解锁页。
///
/// 两个行为刻意做得"保守过头"，理由都必须写清楚：
/// ① **状态读不出来 = 不锁**（[appLockEnabledProvider] 已兜底为 false）。
///    把用户锁在自己的数据外面是最糟的失败模式，没有之一；
/// ② **切到后台就立刻重新上锁**，而不是"离开 30 秒才算超时"。
///    计时方案要么太短烦人、要么太长形同虚设；而"看不见 App 就等于退出"
///    这条规则既简单又符合直觉——把手机递给别人时，界面回到锁屏才是预期行为。
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child, this.biometrics});

  final Widget child;

  /// 仅供测试注入假的生物识别（真机上的实现要调平台通道，测试里不可用）
  final BiometricUnlock? biometrics;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _biometricsAvailable = false;

  BiometricUnlock get _biometrics => widget.biometrics ?? BiometricUnlock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeBiometrics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_unlocked) return;
      setState(() => _unlocked = false);
    }
  }

  Future<void> _probeBiometrics() async {
    final available = await _biometrics.isAvailable;
    if (!mounted) return;
    setState(() => _biometricsAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    // valueOrNull 而不是 when：这里是"要不要展示拦门页"，
    // 用 AsyncValue.when 会让加载态把已经加载好的内容重新推回去闪一下。
    final enabled = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
    if (!enabled || _unlocked) return widget.child;

    final actions = ref.read(appLockActionsProvider);
    return AppLockScreen(
      verify: actions.verify,
      onUnlocked: () => setState(() => _unlocked = true),
      biometrics: widget.biometrics,
      biometricsAvailable: _biometricsAvailable,
    );
  }
}
