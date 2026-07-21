// FaceStyle 앱 스모크 테스트.
//
// 저장된 로그인 토큰이 없으면 로그인 화면으로 리다이렉트되는지 확인한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facestyle/main.dart';

void main() {
  testWidgets('토큰이 없으면 로그인 화면으로 부팅된다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({}); // 저장된 토큰 없음 → 로그아웃 상태
    await tester.pumpWidget(const ProviderScope(child: FaceStyleApp()));
    await tester.pumpAndSettle();

    expect(find.text('FaceStyle'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });
}
