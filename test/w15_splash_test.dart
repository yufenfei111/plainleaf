import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plainleaf/app/splash_transition.dart';

/// W15 启动过场（需求 1）
///
/// 这个文件的重点不是"动画好不好看"，而是**守住三条不影响既有行为的约定**：
/// child 始终在树中、过场层不拦截点击、动画结束后必须能静止。
/// 这三条一旦破掉，受伤的是整套既有测试（find/tap/pumpAndSettle）。
void main() {
  Widget wrap(Widget child, {bool enabled = true}) => MaterialApp(
        home: SplashTransition(enabled: enabled, child: child),
      );

  testWidgets('① 过场期间：主界面已在树中，且点击能穿透', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(
      GestureDetector(
        onTap: () => tapped++,
        child: const Text('主界面内容'),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('splash-overlay')), findsOneWidget,
        reason: '过场层应该在');
    expect(find.text('主界面内容'), findsOneWidget,
        reason: 'child 必须始终在树中 —— 否则所有 find.* 断言都会失败');

    await tester.tap(find.text('主界面内容'));
    expect(tapped, 1, reason: '过场层必须让点击穿透');
  });

  testWidgets('② 过场结束后：层消失，且没有任何动画还在跑', (tester) async {
    await tester.pumpWidget(wrap(const Text('主界面内容')));
    await tester.pump();
    expect(find.byKey(const Key('splash-overlay')), findsOneWidget);

    // 推过总时长（880ms）
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('splash-overlay')), findsNothing);
    expect(find.text('主界面内容'), findsOneWidget);

    // 守护"不留常驻 ticker"：这里若能立刻静止，说明动画确实结束了。
    // 若有循环动画，这一行会挂到超时（本项目 W10/W13 各踩过一次）。
    await tester.pumpAndSettle();
  });

  testWidgets('③ enabled=false：完全不出现过场层', (tester) async {
    await tester.pumpWidget(wrap(const Text('主界面内容'), enabled: false));
    await tester.pump();

    expect(find.byKey(const Key('splash-overlay')), findsNothing);
    expect(find.text('主界面内容'), findsOneWidget);
  });

  testWidgets('④ 系统「减少动态效果」开启时跳过过渡（无障碍）', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: SplashTransition(child: const Text('主界面内容')),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('splash-overlay')), findsNothing);
    expect(find.text('主界面内容'), findsOneWidget);
  });

  testWidgets('⑤ 过场不引入任何可被 find.text 命中的文字（不干扰既有断言）', (tester) async {
    await tester.pumpWidget(wrap(const Text('主界面内容')));
    await tester.pump();

    // 过场里那两个字用的是 RichText：find.text 默认不匹配它，
    // 所以整个 App 里「素页」这两个字不会凭空多出一个候选。
    expect(find.text('素页'), findsNothing);
  });
}
