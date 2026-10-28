import 'package:flutter_test/flutter_test.dart';

import 'package:image_dedup/main.dart';

void main() {
  testWidgets('应用启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // 顶部工具栏核心元素存在
    expect(find.text('选择文件夹'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('相似阈值'), findsOneWidget);
  });
}
