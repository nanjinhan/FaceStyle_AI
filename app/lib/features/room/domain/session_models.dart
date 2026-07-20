/// 실시간 방(세션) 도메인 모델.
///
/// 백엔드 계약(backend/app/schemas.py: SessionDetail 등)을 그대로 반영한다.
/// 서버 JSON은 camelCase 키(inviteToken, claimedByMemberId 등)를 쓴다.
library;

class SessionDetail {
  const SessionDetail({
    required this.id,
    required this.status,
    required this.inviteToken,
    required this.inviteCode,
    required this.maxMembers,
    required this.expiresAt,
    required this.members,
    required this.photos,
  });

  final String id;

  /// active | locked | expired
  final String status;
  final String inviteToken;
  final String inviteCode;
  final int maxMembers;
  final DateTime expiresAt;
  final List<Member> members;
  final List<Photo> photos;

  bool get isLocked => status != 'active';

  factory SessionDetail.fromJson(Map<String, dynamic> json) => SessionDetail(
        id: json['id'] as String,
        status: json['status'] as String,
        inviteToken: json['inviteToken'] as String,
        inviteCode: json['inviteCode'] as String,
        maxMembers: json['maxMembers'] as int,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        members: (json['members'] as List<dynamic>)
            .map((m) => Member.fromJson(m as Map<String, dynamic>))
            .toList(),
        photos: (json['photos'] as List<dynamic>)
            .map((p) => Photo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class Member {
  const Member({
    required this.id,
    required this.nickname,
    required this.role,
    required this.connected,
  });

  final String id;
  final String nickname;

  /// host | guest
  final String role;
  final bool connected;

  bool get isHost => role == 'host';

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        role: json['role'] as String,
        connected: json['connected'] as bool? ?? false,
      );
}

/// 사진 한 장의 완료 확정 현황 (명세 3·4장 "완료 확정").
///
/// 분모(`requiredMembers`)는 그 사진에서 얼굴을 클레임한 사람들이다
/// — 명세 4장 "사진 속 클레임 인원 기준으로 계산 (예: 2/3 완료)".
/// 전원이 완료하면 서버가 자동 확정하고 편집을 잠근다.
class CompletionState {
  const CompletionState({
    this.completed = const [],
    this.requiredMembers = const [],
    this.finalized = false,
  });

  final List<String> completed;
  final List<String> requiredMembers;
  final bool finalized;

  int get doneCount => completed.length;
  int get totalCount => requiredMembers.length;

  /// 아무도 얼굴을 지정하지 않아 완료 체크 자체가 불가능한 상태.
  bool get hasNobody => requiredMembers.isEmpty;

  bool isDoneBy(String? memberId) => memberId != null && completed.contains(memberId);

  /// 이 사람이 완료 체크를 해야 하는 대상인지.
  bool isRequiredOf(String? memberId) => memberId != null && requiredMembers.contains(memberId);

  factory CompletionState.fromJson(Map<String, dynamic> json) => CompletionState(
        completed: ((json['completed'] ?? json['completedBy']) as List<dynamic>? ?? const [])
            .map((v) => v as String)
            .toList(),
        requiredMembers: ((json['required'] ?? json['requiredBy']) as List<dynamic>? ?? const [])
            .map((v) => v as String)
            .toList(),
        finalized: json['finalized'] as bool? ?? false,
      );
}

class Photo {
  const Photo({
    required this.id,
    required this.url,
    required this.width,
    required this.height,
    required this.faces,
    required this.editState,
    this.completion = const CompletionState(),
  });

  final String id;
  final String url;
  final int width;
  final int height;
  final List<Face> faces;
  final EditState editState;
  final CompletionState completion;

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
        id: json['id'] as String,
        url: json['url'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        faces: (json['faces'] as List<dynamic>)
            .map((f) => Face.fromJson(f as Map<String, dynamic>))
            .toList(),
        editState: EditState.fromJson(json['editState'] as Map<String, dynamic>),
        completion: CompletionState.fromJson(json),
      );

  Photo copyWith({List<Face>? faces, EditState? editState, CompletionState? completion}) => Photo(
        id: id,
        url: url,
        width: width,
        height: height,
        faces: faces ?? this.faces,
        editState: editState ?? this.editState,
        completion: completion ?? this.completion,
      );
}

class Face {
  const Face({
    required this.id,
    required this.faceIndex,
    required this.bbox,
    required this.claimedByMemberId,
  });

  final String id;
  final int faceIndex;

  /// [x, y, w, h] — 원본 이미지 픽셀 좌표.
  final List<int> bbox;
  final String? claimedByMemberId;

  bool get isClaimed => claimedByMemberId != null;

  /// 파라미터 경로용 식별자. 예: "faces.face_0.skinSmooth"
  String get pathKey => 'face_$faceIndex';

  factory Face.fromJson(Map<String, dynamic> json) => Face(
        id: json['id'] as String,
        faceIndex: json['faceIndex'] as int,
        bbox: (json['bbox'] as List<dynamic>).map((v) => v as int).toList(),
        claimedByMemberId: json['claimedByMemberId'] as String?,
      );

  Face copyWith({Object? claimedByMemberId = _sentinel}) => Face(
        id: id,
        faceIndex: faceIndex,
        bbox: bbox,
        claimedByMemberId: claimedByMemberId == _sentinel
            ? this.claimedByMemberId
            : claimedByMemberId as String?,
      );

  static const _sentinel = Object();
}

/// 사진 한 장의 보정 파라미터. 백엔드 collab/state.py 와 동일 구조.
///  - version: 단조 증가 (LWW 기준)
///  - global:  전역 보정 (brightness/contrast/saturation/colorTemp/...)
///  - faces:   { "face_0": {skinSmooth:..., ...}, ... }
class EditState {
  EditState({
    required this.photoId,
    required this.version,
    required this.global,
    required this.faces,
  });

  final String photoId;
  int version;
  final Map<String, dynamic> global;
  final Map<String, Map<String, dynamic>> faces;

  factory EditState.fromJson(Map<String, dynamic> json) => EditState(
        photoId: json['photoId'] as String,
        version: json['version'] as int,
        global: Map<String, dynamic>.from(json['global'] as Map),
        faces: (json['faces'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        ),
      );

  /// "global.brightness" / "faces.face_0.skinSmooth" 경로로 값 읽기.
  dynamic valueAt(String path) {
    final parts = path.split('.');
    if (parts.first == 'global') {
      return _dig(global, parts.sublist(1));
    }
    if (parts.first == 'faces') {
      final face = faces[parts[1]];
      if (face == null) return null;
      return _dig(face, parts.sublist(2));
    }
    return null;
  }

  /// 경로에 값 쓰기. faces 하위 경로면 없는 face 맵을 생성한다.
  void setAt(String path, dynamic value) {
    final parts = path.split('.');
    if (parts.first == 'global') {
      _bury(global, parts.sublist(1), value);
    } else if (parts.first == 'faces') {
      final face = faces.putIfAbsent(parts[1], () => <String, dynamic>{});
      _bury(face, parts.sublist(2), value);
    }
  }

  static dynamic _dig(Map<String, dynamic> node, List<String> parts) {
    dynamic cur = node;
    for (final p in parts) {
      if (cur is! Map || !cur.containsKey(p)) return null;
      cur = cur[p];
    }
    return cur;
  }

  static void _bury(Map<String, dynamic> node, List<String> parts, dynamic value) {
    var cur = node;
    for (var i = 0; i < parts.length - 1; i++) {
      cur = cur.putIfAbsent(parts[i], () => <String, dynamic>{}) as Map<String, dynamic>;
    }
    cur[parts.last] = value;
  }
}
