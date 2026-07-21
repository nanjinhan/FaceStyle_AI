/// 로그인한 유저 (백엔드 UserOut 과 1:1).
class AppUser {
  const AppUser({
    required this.id,
    required this.nickname,
    this.profileImage,
    this.color,
  });

  final String id;
  final String nickname;
  final String? profileImage;

  /// 가입 시 배정된 고유 색상 "#RRGGBB" (명세 1장 — 고유 색상 배정).
  final String? color;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        profileImage: json['profile_image'] as String?,
        color: json['color'] as String?,
      );
}
