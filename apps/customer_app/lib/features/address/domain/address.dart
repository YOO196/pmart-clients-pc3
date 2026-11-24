import 'package:flutter/foundation.dart';

/// 권역 판정 사본. "주소 저장 성공"과 따로 보인다(C 847).
enum Serviceability { serviceable, outOfArea, unknown }

enum EntranceMethod { free, password, call, other }

@immutable
class Address {
  const Address({
    required this.addressId,
    required this.version,
    required this.roadAddress,
    required this.detailAddress,
    required this.serviceability,
    this.receiverName,
    this.label,
    this.entranceMethod,
    this.mfcId,
  });

  final String addressId;
  final int version;
  final String? label;
  final String roadAddress;
  final String detailAddress;

  /// 받는 분. customer 0.8.0(BR-60)부터 없을 수 있다 — 주문 때 서버가 프로필 이름으로 채운다.
  final String? receiverName;
  final EntranceMethod? entranceMethod;
  final Serviceability serviceability;

  /// 판정된 담당 센터. 판정 전·권역 밖이면 null.
  final String? mfcId;
}

/// 고객이 입력한 주소. 출입 비밀번호(entranceNote)·전화번호는 로그에 남기지 않는다.
@immutable
class AddressDraft {
  const AddressDraft({
    required this.roadAddress,
    required this.detailAddress,
    this.receiverName,
    this.receiverPhone,
    this.label,
    this.entranceMethod,
    this.entranceNote,
    this.geo,
    this.postalCode,
  });

  final String? label;
  final String roadAddress;
  final String detailAddress;

  /// 받는 분·연락처. customer 0.8.0(BR-60 R1)부터 보내지 않아도 된다 — 주문 초안이 회원 프로필 값을 쓴다.
  /// 주소 입력 화면은 보내지 않고, 비회원 배송지를 회원 주소록으로 옮길 때만 그 값이 남아 있으면 그대로 옮긴다.
  final String? receiverName;
  final String? receiverPhone;
  final EntranceMethod? entranceMethod;
  final String? entranceNote;

  /// 좌표(계약 `AddressInput.geo`). 서버가 이것으로 배송 가능·담당 센터를 판정한다.
  /// 주소 검색이 붙기 전에는 개발 빌드의 시험 좌표로만 채운다(BR-29).
  final ({double lat, double lng})? geo;

  /// 우편번호(주소 검색 결과).
  final String? postalCode;

  @override
  String toString() => 'AddressDraft(…)';
}

/// 개발 빌드 전용 시험 주소. 카카오 지도가 안 되는 x86 에뮬레이터에서 시험할 때 쓴다.
/// 판정은 도로명으로 하므로(ADR-0023) LAN 시험 권역(부산진구) 안의 실제 도로명주소다.
/// 좌표는 서버 주소 변환 결과(2026-10-31 LAN 확인).
abstract final class DevTestAddress {
  static const roadAddress = '부산 부산진구 중앙대로 672';
  static const postalCode = '47296';
  static const geo = (lat: 35.1529, lng: 129.0596);
}

/// 개발 빌드 전용 센터별 시험 주소 하나 — 그 센터 LAN 시험 배송 권역 안의 실제 도로명주소.
/// 좌표·우편번호는 넣지 않는다 — 버튼을 누르면 주소 검색처럼 서버 주소 변환으로 핀을 잡는다.
@immutable
class DevTestArea {
  const DevTestArea({
    required this.id,
    required this.center,
    required this.roadAddress,
  });

  /// 버튼 키(`dev-test-geo-<id>`).
  final String id;

  /// 버튼에 보일 센터 이름(개발 빌드 전용).
  final String center;
  final String roadAddress;
}

/// 부산진(1호점)은 [DevTestAddress](좌표 고정, 에뮬레이터용). 나머지 센터(사용자 2026-11-23 목포, 2026-11-24 세종·그 밖):
/// - 목포 `MFC-MOKPO-01` 권역 "목포 시내" — LAN 목포 시험 고객 주소(pmart-backend lan-test-accounts §2-1).
/// - 세종 `MFC-SEJ-01` 권역 `Z-SEED-SEJONG`(127.23~127.32·36.46~36.54) — 세종시청(사용자 본인 계정 쇼핑 주소와 같은 곳).
/// - 춘천 `MFC-CHC-01` 권역 `Z-SEED-CHUNCHEON`(127.69~127.78·37.84~37.91) — 춘천시청.
/// - 부산 남구 `MFC-BNG-01` 권역 `Z-SEED-BUSANNAMGU`(129.081~129.13·35.10~35.15) — 부경대 대연캠퍼스.
/// 권역 출처: pmart-backend docs/handoff/simulator/mfc/2026-11-23~24 센터 요청서 §작업 표.
abstract final class DevTestAreas {
  static const all = [
    DevTestArea(id: 'mokpo', center: '목포점', roadAddress: '전남 목포시 평화로83번길 16'),
    DevTestArea(id: 'sejong', center: '세종점', roadAddress: '세종특별자치시 한누리대로 2130'),
    DevTestArea(
      id: 'chuncheon',
      center: '춘천점',
      roadAddress: '강원특별자치도 춘천시 중앙로 1',
    ),
    DevTestArea(
      id: 'busan-namgu',
      center: '부산 남구점',
      roadAddress: '부산 남구 용소로 45',
    ),
  ];
}

/// 계약 `AddressInput` maxLength. 화면 입력 상한으로만 쓴다(서버가 최종 검증).
abstract final class AddressLimits {
  static const label = 20;
  static const roadAddress = 200;
  static const detailAddress = 200;
  static const receiverName = 50;
  static const receiverPhone = 20;
  static const entranceNote = 100;
}

@immutable
class ShoppingContext {
  const ShoppingContext({
    required this.version,
    this.shoppingAddressId,
    this.mfcId,
  });

  final String? shoppingAddressId;
  final String? mfcId;

  /// 쇼핑 주소 선택의 expectedVersion.
  final int version;
}

@immutable
class AddressBook {
  const AddressBook({required this.addresses, required this.context});

  final List<Address> addresses;
  final ShoppingContext context;

  Address? get shoppingAddress => addresses
      .where((a) => a.addressId == context.shoppingAddressId)
      .firstOrNull;
}
