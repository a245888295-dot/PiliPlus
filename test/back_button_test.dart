import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:PiliPlus/common/widgets/floating_back_button.dart';

Widget _app(GlobalKey<NavigatorState> key, VoidCallback onBack) {
  return MaterialApp(
    navigatorKey: key,
    navigatorObservers: [BackStackObserver.instance],
    builder: (context, child) =>
        BackButtonOverlay(onBack: onBack, child: child!),
    home: const Scaffold(body: Center(child: Text('home'))),
  );
}

Future<void> _pushList(WidgetTester tester, GlobalKey<NavigatorState> key) async {
  key.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: ListView.builder(
          itemCount: 50,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('item $i')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _fabBottom(WidgetTester tester) =>
    tester.getRect(find.byType(FloatingActionButton)).bottom;

double _fabTop(WidgetTester tester) =>
    tester.getRect(find.byType(FloatingActionButton)).top;

void main() {
  setUp(() => BackStackObserver.instance.canPop.value = false);

  testWidgets('根页面不显示，push 后滑入，点击触发 onBack', (tester) async {
    final key = GlobalKey<NavigatorState>();
    var backs = 0;
    await tester.pumpWidget(_app(key, () => backs++));
    await tester.pumpAndSettle();

    // 600 高的测试屏，按钮隐藏时整体在屏幕外
    expect(_fabTop(tester), greaterThanOrEqualTo(600));

    await _pushList(tester, key);
    expect(_fabBottom(tester), closeTo(520, 1));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('向下滚动收起，停手后滑回', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, () {}));
    await tester.pumpAndSettle();
    await _pushList(tester, key);
    expect(_fabBottom(tester), closeTo(520, 1));

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_fabTop(tester), greaterThanOrEqualTo(600));

    // _kIdleDelay = 700ms
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(_fabBottom(tester), closeTo(520, 1));
  });

  testWidgets('往回滚立刻放出来', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, () {}));
    await tester.pumpAndSettle();
    await _pushList(tester, key);

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_fabTop(tester), greaterThanOrEqualTo(600));

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_fabBottom(tester), closeTo(520, 1));
  });

  testWidgets('pop 回根页面后收起', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, () {}));
    await tester.pumpAndSettle();
    await _pushList(tester, key);
    expect(_fabBottom(tester), closeTo(520, 1));

    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_fabTop(tester), greaterThanOrEqualTo(600));
  });

  testWidgets('键盘弹出时收起', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, () {}));
    await tester.pumpAndSettle();
    await _pushList(tester, key);
    expect(_fabBottom(tester), closeTo(520, 1));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(_fabTop(tester), greaterThanOrEqualTo(600));
  });

  testWidgets('外观快照', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, () {}));
    await tester.pumpAndSettle();
    await _pushList(tester, key);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('back_button.png'),
    );
  });
}
