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
    required this.receiverName,
    required this.serviceability,
    this.label,
    this.entranceMethod,
    this.mfcId,
  });

  final String addressId;
  final int version;
  final String? label;
  final String roadAddress;
  final String detailAddress;
  final String receiverName;
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
    required this.receiverName,
    required this.receiverPhone,
    this.label,
    this.entranceMethod,
    this.entranceNote,
  });

  final String? label;
  final String roadAddress;
  final String detailAddress;
  final String receiverName;
  final String receiverPhone;
  final EntranceMethod? entranceMethod;
  final String? entranceNote;

  @override
  String toString() => 'AddressDraft(…)';
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
