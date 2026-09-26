import 'package:local_auth/local_auth.dart';

/// 生物识别解锁（W14）
///
/// 定位：**它是"快速通道"，不是"唯一通道"**。这句话决定了下面所有实现细节——
/// - 任何失败（没硬件、没录指纹、用户取消、插件在桌面端直接抛缺失异常）
///   一律降级：返回 false / 不可用，UI 退回密码输入。用户永远有一条能走通的路。
/// - 不用 `stickyAuth`：用素页的场景是"切回来快速解锁"，不是支付二次确认，
///   在后台时反复弹系统验证框是自找投诉。
///
/// 与 [AppLockService] 的关系：本类只回答"操作者是不是机主"，不参与任何密钥派生。
/// 因为应用锁是**本机交互门槛**而不是数据加密密钥（见 AppLockService 类注释），
/// 指纹通过后直接放行即可，不需要拿什么秘密去"续费"。
class BiometricUnlock {
  BiometricUnlock({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// 是否提供生物识别入口。
  ///
  /// 先探一次再决定要不要显示按钮：设备支持但**从未录过指纹**时，
  /// 直接调 authenticate 会弹出一个系统错误框，那是我们自己引来的坏体验。
  Future<bool> get isAvailable async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// 弹系统验证；通过返回 true，任何异常都按"没通过"处理
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: '验证指纹以打开素页',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } on Object {
      return false;
    }
  }
}
