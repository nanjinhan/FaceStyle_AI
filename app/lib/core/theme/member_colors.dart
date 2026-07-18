import 'package:flutter/material.dart';

/// 유저 고유 색상 (명세: 회원관리 — 고유 색상 배정).
///
/// 색상 배정의 원본(source of truth)은 서버(User.color, hex 문자열)이며,
/// 이 팔레트는 서버가 배정할 때 쓰는 후보군과 동일하게 유지한다.
/// 커서·프로필·상태 아이콘·클레임 테두리에 모두 이 색을 쓴다.
abstract final class MemberColors {
  static const palette = <Color>[
    Color(0xFFF4573D), // 토마토
    Color(0xFFFB9E4E), // 오렌지
    Color(0xFFF7C948), // 옐로우
    Color(0xFF4CB782), // 그린
    Color(0xFF35A2C9), // 시안
    Color(0xFF5A6AE8), // 블루
    Color(0xFF9A5AE8), // 퍼플
    Color(0xFFE85A9C), // 핑크
  ];

  /// 서버가 주는 "#RRGGBB" hex를 Color로 변환. 파싱 실패 시 memberId 해시로 폴백.
  static Color fromHex(String? hex, {String fallbackSeed = ''}) {
    if (hex != null) {
      final cleaned = hex.replaceFirst('#', '');
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null && cleaned.length == 6) {
        return Color(0xFF000000 | value);
      }
    }
    return palette[fallbackSeed.hashCode.abs() % palette.length];
  }
}
