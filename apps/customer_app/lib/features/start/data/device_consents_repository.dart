import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../../profile/data/consents_repository.dart'
    show ConsentChange, ConsentProblemCode, ConsentWire;

/// 약관 한 항목(customer 0.6.0 `GET /consent-terms`). 버전은 서버 값 그대로 — 앱에 두지 않는다.
@immutable
class ConsentTerm {
  const ConsentTerm({
    required this.type,
    required this.required,
    required this.latestVersion,
    this.requiredFor,
    this.hasDocument = false,
  });

  final String type;
  final bool required;

  /// 이 기능을 쓸 때만 필수(위치 약관 = `CURRENT_LOCATION`). 없으면 null.
  final String? requiredFor;
  final String latestVersion;

  /// 서버에 본문이 있다(`documentUrl` 있음) — `>` 로 펼쳐 본다.
  final bool hasDocument;
}

@immutable
class ConsentTerms {
  const ConsentTerms({required this.items, this.senderName});

  final List<ConsentTerm> items;
  final String? senderName;

  ConsentTerm? of(String type) =>
      items.where((t) => t.type == type).firstOrNull;
}

/// 약관 본문(0.6.1, Markdown).
@immutable
class ConsentTermDocument {
  const ConsentTermDocument({
    required this.type,
    required this.version,
    required this.title,
    required this.body,
  });

  final String type;
  final String version;
  final String title;

  /// Markdown(제목 줄 포함).
  final String body;
}

/// 로그인 전(기기) 동의 한 항목. [lastChangedAt] 은 서버가 처리한 시각 — "수신동의 처리완료" 안내에 쓴다.
@immutable
class DeviceConsent {
  const DeviceConsent({
    required this.type,
    required this.agreed,
    this.version,
    this.lastChangedAt,
  });

  final String type;
  final bool agreed;
  final String? version;
  final DateTime? lastChangedAt;
}

@immutable
class DeviceConsents {
  const DeviceConsents({required this.items, this.senderName});

  final List<DeviceConsent> items;

  /// 수신 동의 처리 결과 안내의 전송자(서버 설정, 없으면 null).
  final String? senderName;

  DeviceConsent? of(String type) =>
      items.where((c) => c.type == type).firstOrNull;
}

/// 처음 실행 약관(BR-59 회신, customer 0.6.0~0.6.1). 토큰 없이 기기 ID 로 보낸다 — 로그인하면 서버가 계정으로 옮긴다.
abstract interface class DeviceConsentsRepository {
  /// `GET /consent-terms`(토큰 없음).
  Future<ConsentTerms> terms();

  /// `GET /consent-terms/{type}/{version}`(토큰 없음). 없으면 404 `CONSENT_TERM_NOT_FOUND`.
  Future<ConsentTermDocument> document(String type, String version);

  /// `GET /device-consents`(X-Device-Id). 로그인해 계정으로 옮긴 뒤에는 고르지 않은 상태로 온다.
  Future<DeviceConsents> list();

  /// `POST /device-consent-changes`(X-Device-Id). 응답 = 반영 뒤 상태. 같은 키 재전송은 다시 반영하지 않는다.
  Future<DeviceConsents> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  });
}

api.ConsentType _type(String wire) => api.ConsentType.values.firstWhere(
  (v) => v.value == wire,
  orElse: () => throw ContractViolationFailure('모르는 동의 항목 $wire'),
);

final class ApiDeviceConsentsRepository implements DeviceConsentsRepository {
  ApiDeviceConsentsRepository(Dio dio, this._deviceId)
    : _api = api.PmartApiCustomer(dio: dio).getDeviceConsentsApi();

  final api.DeviceConsentsApi _api;
  final DeviceIdProvider _deviceId;

  @override
  Future<ConsentTerms> terms() async {
    final res = await pmartGuard(() => _api.listConsentTerms());
    final body =
        res.data ?? (throw const ContractViolationFailure('약관 목록 본문 없음'));
    return ConsentTerms(
      senderName: body.senderName,
      items: [
        for (final t in body.items)
          ConsentTerm(
            type: t.consentType.value,
            required: t.required_,
            requiredFor: t.requiredFor?.value,
            latestVersion: t.latestVersion,
            hasDocument: t.documentUrl != null,
          ),
      ],
    );
  }

  @override
  Future<ConsentTermDocument> document(String type, String version) async {
    final res = await pmartGuard(
      () => _api.getConsentTermDocument(
        consentType: _type(type),
        version: version,
      ),
    );
    final d = res.data ?? (throw const ContractViolationFailure('약관 본문 없음'));
    return ConsentTermDocument(
      type: d.consentType.value,
      version: d.version,
      title: d.title,
      body: d.body,
    );
  }

  @override
  Future<DeviceConsents> list() async {
    final deviceId = await _deviceId.get();
    final res = await pmartGuard(
      () => _api.listDeviceConsents(xDeviceId: deviceId),
    );
    return deviceConsentsFromContract(
      res.data ?? (throw const ContractViolationFailure('기기 동의 본문 없음')),
    );
  }

  @override
  Future<DeviceConsents> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  }) async {
    final deviceId = await _deviceId.get();
    final res = await pmartGuard(
      () => _api.changeDeviceConsents(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xDeviceId: deviceId,
        changeMyConsentsRequest: api.ChangeMyConsentsRequest(
          changes: [
            for (final c in changes)
              api.ChangeMyConsentsRequestChangesInner(
                consentType: _type(c.type),
                version: c.version,
                agreed: c.agreed,
              ),
          ],
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return deviceConsentsFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }
}

DeviceConsents deviceConsentsFromContract(api.DeviceConsentList r) =>
    DeviceConsents(
      senderName: r.senderName,
      items: [
        for (final c in r.items)
          DeviceConsent(
            type: c.consentType.value,
            agreed: c.agreed,
            version: c.version,
            lastChangedAt: c.lastChangedAt,
          ),
      ],
    );

/// ⚠ 화면 개발·시험용 목. 버전·전송자는 LAN 서버 값(2026-11-19 `GET /consent-terms`)과 같게 둔다.
final class MockDeviceConsentsRepository implements DeviceConsentsRepository {
  MockDeviceConsentsRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final changes = <(List<ConsentChange>, String)>[];
  final _state = <String, DeviceConsent>{};
  final _keys = <String>{};
  PmartFailure? failNextTerms;
  PmartFailure? failNextChange;

  static const sender = 'PMart';
  static const _terms = [
    ConsentTerm(
      type: ConsentWire.terms,
      required: true,
      latestVersion: '2026-11-17',
      hasDocument: true,
    ),
    ConsentTerm(
      type: ConsentWire.privacy,
      required: true,
      latestVersion: '2026-11-17',
      hasDocument: true,
    ),
    ConsentTerm(
      type: ConsentWire.age14,
      required: true,
      latestVersion: '1',
      hasDocument: true,
    ),
    ConsentTerm(
      type: ConsentWire.marketing,
      required: false,
      latestVersion: '2026-11-17',
      hasDocument: true,
    ),
    ConsentTerm(
      type: ConsentWire.location,
      required: false,
      requiredFor: 'CURRENT_LOCATION',
      latestVersion: '2026-11-19',
      hasDocument: true,
    ),
  ];

  @override
  Future<ConsentTerms> terms() async {
    if (failNextTerms case final f?) {
      failNextTerms = null;
      throw f;
    }
    return const ConsentTerms(items: _terms, senderName: sender);
  }

  @override
  Future<ConsentTermDocument> document(String type, String version) async {
    final t = _terms.where((t) => t.type == type).firstOrNull;
    if (t == null || t.latestVersion != version) {
      throw const ProblemFailure(
        Problem(status: 404, code: 'CONSENT_TERM_NOT_FOUND'),
      );
    }
    // 실서버는 본문 첫 줄 제목(# 뒤)을 title 로 준다. 목도 내부 코드 대신 약관 이름을 쓴다.
    final name = switch (type) {
      ConsentWire.terms => '이용약관',
      ConsentWire.privacy => '개인정보 수집·이용',
      ConsentWire.age14 => '만 14세 이상 확인',
      ConsentWire.marketing => '마케팅 정보 수신',
      ConsentWire.location => '위치기반서비스 이용약관',
      _ => '약관',
    };
    return ConsentTermDocument(
      type: type,
      version: version,
      title: name,
      body:
          '# $name\n\n[목] 시연용 약관 본문입니다.\n\n| 항목 | 내용 |\n|---|---|\n| 버전 | $version |\n',
    );
  }

  DeviceConsents _snapshot() => DeviceConsents(
    senderName: sender,
    items: [
      for (final type in [ConsentWire.marketing, ConsentWire.location])
        _state[type] ?? DeviceConsent(type: type, agreed: false),
    ],
  );

  @override
  Future<DeviceConsents> list() async => _snapshot();

  @override
  Future<DeviceConsents> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  }) async {
    this.changes.add((changes, key.value));
    if (failNextChange case final f?) {
      failNextChange = null;
      throw f;
    }
    if (_keys.add(key.value)) {
      for (final c in changes) {
        final t = _terms.where((t) => t.type == c.type).firstOrNull;
        if (t == null || t.required) {
          throw const ProblemFailure(
            Problem(status: 400, code: 'VALIDATION_FAILED'),
          );
        }
        if (t.latestVersion != c.version) {
          throw const ProblemFailure(
            Problem(status: 422, code: ConsentProblemCode.versionOutdated),
          );
        }
        _state[c.type] = DeviceConsent(
          type: c.type,
          agreed: c.agreed,
          version: c.version,
          lastChangedAt: _now().toUtc(),
        );
      }
    }
    return _snapshot();
  }
}
