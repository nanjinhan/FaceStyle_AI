// FaceStyle 앱 스모크 테스트.
//
// 앱이 로그인 화면(initialLocation '/login')으로 정상 부팅되는지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facestyle/main.dart';

void main() {
  testWidgets('앱이 로그인 화면으로 부팅된다', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FaceStyleApp()));
    await tester.pumpAndSettle();

    // 로그인 화면의 타이틀과 시작 버튼이 보인다.
    expect(find.text('FaceStyle'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
