import 'dart:async';

/// 简单防抖器：区间内的连续调用只触发最后一次（§5.2：自动保存 500ms 防抖）
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 500)});

  final Duration duration;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// 立即执行挂起的动作并取消计时（页面关闭前冲刷保存）
  void flush(void Function() action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}