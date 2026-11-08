import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_account_page.dart';

void main() {
  testWidgets(
    'account login, registration and reset without debug or explanatory copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CycaniAccountPage(embedded: true)),
        ),
      );
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('导入令牌'), findsNothing);
      expect(find.textContaining('Kazumi'), findsNothing);
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      expect(find.text('昵称'), findsOneWidget);
      expect(find.text('邮箱'), findsOneWidget);
      await tester.tap(find.text('重置密码').first);
      await tester.pumpAndSettle();
      expect(find.text('新密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
