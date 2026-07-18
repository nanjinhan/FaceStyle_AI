/// 백엔드 주소 설정.
///
/// 개발 시:
///  - Android 에뮬레이터: http://10.0.2.2:8000 (호스트 PC의 localhost)
///  - iOS 시뮬레이터:    http://localhost:8000
///  - 실기기:            PC의 LAN IP (예: http://192.168.0.10:8000)
///
/// `--dart-define=API_BASE_URL=...` 으로 빌드 시 교체할 수 있다.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static String get wsBaseUrl =>
      apiBaseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

  /// 초대 딥링크 스킴 (docs/아키텍처.md — 인증·초대)
  static const deepLinkScheme = 'facestyle';
}
