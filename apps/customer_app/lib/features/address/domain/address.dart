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

/// 개발 빌드 전용 목포 시험 주소(2호점 `MFC-MOKPO-01` 시험 권역 "목포 시내" 안, 사용자 2026-11-23).
/// 백엔드 LAN 목포 시험 고객이 쓰는 주소(→ 쇼핑 센터 MFC-MOKPO-01 확인, pmart-backend lan-test-accounts §3).
/// 좌표·우편번호는 넣지 않는다 — 버튼을 누르면 주소 검색처럼 서버 주소 변환으로 핀을 잡는다.
abstract final class DevTestAddressMokpo {
  static const roadAddress = '전남 목포시 평화로83번길 16';
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
