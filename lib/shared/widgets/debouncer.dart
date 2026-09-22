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

  /// 异步版冲刷：返回 action 的 Future，调用方可以 await。
  ///
  /// 存在理由：发布/退出时要保证「内容写库」先于「状态置 normal」，
  /// 用同步 [flush] 拿不到 Future，两个事务会并发抢锁（FTS 行先被旧内容重写）。
  Future<void> flushAsync(Future<void> Function() action) async {
    _timer?.cancel();
    _timer = null;
    await action();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}