import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../address/domain/address.dart' show EntranceMethod;
import '../domain/checkout.dart';

String entranceMethodText(AppLocalizations l10n, EntranceMethod m) =>
    switch (m) {
      EntranceMethod.free => l10n.entranceFree,
      EntranceMethod.password => l10n.entrancePassword,
      EntranceMethod.call => l10n.entranceCall,
      EntranceMethod.other => l10n.entranceOther,
    };

/// 주문 당시 배송지 사본(BR-37). [address] 가 null 이면 "배송지 정보 없음"이다 —
/// 주소록의 현재 주소를 대신 보이지 않는다(배포 전 주문·사본 없음).
class ShippingAddressView extends StatelessWidget {
  const ShippingAddressView({super.key, required this.address});

  final ShippingAddress? address;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = address;
    if (a == null) {
      return Text(
        l10n.shippingAddressUnavailable,
        key: const ValueKey('shipping-address-none'),
      );
    }
    final entrance = [
      if (a.entranceMethod case final m?) entranceMethodText(l10n, m),
      ?a.entranceNote,
    ].join(' · ');
    return Column(
      key: const ValueKey('shipping-address'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${a.roadAddress} ${a.detailAddress}'.trim()),
        Text(l10n.receiverLine(a.receiverName, a.receiverPhone)),
        if (entrance.isNotEmpty) Text(entrance),
      ],
    );
  }
}
