import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// 형태 토큰(반경·간격) — 위젯 공용. 색은 테마 ColorScheme / [Brand] 에서 가져온다.
abstract final class UiTokens {
  static const radius = 14.0; // 버튼·인풋
  static const radiusLg = 20.0; // 카드
  static const gap = 12.0;
}

/// 브랜드 로고 마크 — 보라 그라데이션 사각형 위의 아이콘.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.radius = 12, this.icon = 22});

  final double size;
  final double radius;
  final double icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Brand.gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Brand.softShadow(y: 6, blur: 16, opacity: 0.35),
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: icon),
    );
  }
}
