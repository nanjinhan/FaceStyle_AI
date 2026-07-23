import 'package:facestyle/core/theme/app_theme.dart';
import 'package:facestyle/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// shadcn 위젯 키트 기본 동작 검증.
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: Center(child: child)));

  group('ShadButton', () {
    testWidgets('탭하면 onPressed 가 호출된다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(ShadButton(onPressed: () => tapped = true, child: const Text('확인'))));
      await tester.tap(find.text('확인'));
      expect(tapped, isTrue);
    });

    testWidgets('loading 이면 눌러도 호출되지 않고 스피너가 뜬다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(ShadButton(onPressed: () => tapped = true, loading: true, child: const Text('확인'))));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ShadButton));
      expect(tapped, isFalse);
    });

    testWidgets('onPressed 가 null 이면 비활성', (tester) async {
      await tester.pumpWidget(host(const ShadButton(onPressed: null, child: Text('비활성'))));
      expect(find.text('비활성'), findsOneWidget);
    });

    testWidgets('variant 별로 만들어진다', (tester) async {
      await tester.pumpWidget(host(Column(
        children: [
          ShadButton.outline(onPressed: () {}, child: const Text('취소')),
          ShadButton.destructive(onPressed: () {}, child: const Text('삭제')),
        ],
      )));
      expect(find.text('취소'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });
  });

  group('ShadCard', () {
    testWidgets('제목·설명·자식을 렌더한다', (tester) async {
      await tester.pumpWidget(host(const ShadCard(
        title: '앨범',
        description: '사진 3 · 멤버 2',
        child: Text('본문'),
      )));
      expect(find.text('앨범'), findsOneWidget);
      expect(find.text('사진 3 · 멤버 2'), findsOneWidget);
      expect(find.text('본문'), findsOneWidget);
    });

    testWidgets('onTap 이 동작한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(ShadCard(title: '탭', onTap: () => tapped = true)));
      await tester.tap(find.text('탭'));
      expect(tapped, isTrue);
    });
  });

  group('ShadInput', () {
    testWidgets('라벨·힌트·에러를 렌더한다', (tester) async {
      await tester.pumpWidget(host(const ShadInput(label: '닉네임', hint: '입력', error: '필수예요')));
      expect(find.text('닉네임'), findsOneWidget);
      expect(find.text('필수예요'), findsOneWidget);
    });
  });
}
