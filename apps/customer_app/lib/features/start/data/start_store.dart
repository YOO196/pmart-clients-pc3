import 'package:flutter/foundation.dart';
import 'package:pmart_core/pmart_core.dart';

/// 처음 실행 단계에서 이 기기에 남기는 것.
@immutable
class StartFlags {
  const StartFlags({required this.welcomeDone, required this.entryDone});

  /// 환영·약관 화면에서 "시작하기"를 눌렀다.
  final bool welcomeDone;

  /// 로그인 또는 둘러보기를 골랐다(한 번 고르면 다시 묻지 않는다 — 로그아웃 뒤에도).
  final bool entryDone;
}

/// 처음 실행 기록 — 어느 단계를 지났는지만 둔다. 동의 값은 서버(기기 동의 `POST /device-consent-changes`,
/// BR-59 회신)가 정본이고 여기에 두지 않는다.
final class StartStore {
  StartStore(this._store);

  static const _welcomeKey = 'pmart.start.welcome';
  static const _entryKey = 'pmart.start.entry';
  static const _lastLoginKey = 'pmart.login.last';

  final SecureKeyValueStore _store;

  Future<StartFlags> read() async => StartFlags(
    welcomeDone: await _store.read(_welcomeKey) != null,
    entryDone: await _store.read(_entryKey) != null,
  );

  /// 서버가 기기 동의를 반영한 뒤 부른다. 값은 지난 시각뿐이다.
  Future<void> completeWelcome({required DateTime at}) =>
      _store.write(_welcomeKey, 'at=${at.toUtc().toIso8601String()}');

  Future<void> completeEntry() => _store.write(_entryKey, '1');

  /// 주소 단계에서 뒤로 — 로그인/둘러보기를 다시 고르게 한다.
  Future<void> reopenEntry() => _store.delete(_entryKey);

  /// 이 기기에서 마지막으로 로그인한 소셜(로그인 화면 "최근 로그인" 표시 — 사용자 폰 캡처 2026-11-25).
  Future<String?> lastLogin() => _store.read(_lastLoginKey);

  Future<void> saveLastLogin(String provider) =>
      _store.write(_lastLoginKey, provider);
}
