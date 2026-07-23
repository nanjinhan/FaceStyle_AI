/// 앨범 도메인 모델 (백엔드 schemas.py 의 Album* 과 1:1).
library;

class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.role,
    required this.memberCount,
    required this.photoCount,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String ownerUserId;
  final String role;
  final int memberCount;
  final int photoCount;
  final String? coverUrl;

  factory AlbumSummary.fromJson(Map<String, dynamic> j) => AlbumSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerUserId: j['ownerUserId'] as String,
        role: j['role'] as String,
        memberCount: j['memberCount'] as int,
        photoCount: j['photoCount'] as int,
        coverUrl: j['coverUrl'] as String?,
      );
}

class AlbumMemberInfo {
  const AlbumMemberInfo({required this.userId, required this.nickname, required this.role, this.color});
  final String userId;
  final String nickname;
  final String role;
  final String? color;

  factory AlbumMemberInfo.fromJson(Map<String, dynamic> j) => AlbumMemberInfo(
        userId: j['userId'] as String,
        nickname: j['nickname'] as String,
        role: j['role'] as String,
        color: j['color'] as String?,
      );
}

class AlbumPhotoInfo {
  const AlbumPhotoInfo({
    required this.id,
    required this.url,
    required this.width,
    required this.height,
    required this.finalized,
  });
  final String id;
  final String url;
  final int width;
  final int height;
  final bool finalized;

  factory AlbumPhotoInfo.fromJson(Map<String, dynamic> j) => AlbumPhotoInfo(
        id: j['id'] as String,
        url: j['url'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        finalized: j['finalized'] as bool? ?? false,
      );
}

class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.inviteToken,
    required this.inviteCode,
    required this.myRole,
    required this.members,
    required this.photos,
  });

  final String id;
  final String name;
  final String ownerUserId;
  final String inviteToken;
  final String inviteCode;
  final String myRole;
  final List<AlbumMemberInfo> members;
  final List<AlbumPhotoInfo> photos;

  bool get amOwner => myRole == 'owner';

  factory AlbumDetail.fromJson(Map<String, dynamic> j) => AlbumDetail(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerUserId: j['ownerUserId'] as String,
        inviteToken: j['inviteToken'] as String,
        inviteCode: j['inviteCode'] as String,
        myRole: j['myRole'] as String,
        members: (j['members'] as List<dynamic>)
            .map((m) => AlbumMemberInfo.fromJson(m as Map<String, dynamic>))
            .toList(),
        photos: (j['photos'] as List<dynamic>)
            .map((p) => AlbumPhotoInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
