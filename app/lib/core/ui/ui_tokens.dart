import 'package:flutter/material.dart';

/// shadcn 디자인 토큰 (위젯 공용). 색상은 테마 ColorScheme 에서 가져오고,
/// 여기서는 반경·간격 같은 형태 토큰만 정의한다.
abstract final class UiTokens {
  static const radius = 8.0; // shadcn --radius
  static const radiusLg = 12.0; // 카드
  static const gap = 12.0;
}

/// 브랜드 로고 마크 — 중립 UI 위에 얹는 작은 아이덴티티.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.radius = 10, this.icon = 22});

  final double size;
  final double radius;
  final double icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: icon),
    );
  }
}
