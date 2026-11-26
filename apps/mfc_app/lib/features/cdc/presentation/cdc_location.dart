import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/location_guide.dart' show tempChipColor;
import '../../../shared/pda_theme.dart';

/// DC 위치 코드를 조각으로 나눈 것 — 백엔드 `docs/simulator/cdc/chilgok-dc.md`
/// CDC-3 `{센터}-{구역}-{층}-{통로}-{베이}-{단}-{슬롯}`(예 `CDC01-C-5-02-24-3-1`),
/// CDC-4 구역 글자(A 냉동·B 냉장·C~H 상온), CDC-5 통로 90 지하 접안·91 출고대기·92 승강기 문, CDC-7 통로 61~89 피킹 선반.
/// 조각은 표시용이고 판정은 서버가 한다. 형식이 아니면 null(코드 그대로 보인다).
@immutable
class CdcLocationCode {
  const CdcLocationCode({
    required this.center,
    required this.zone,
    required this.floor,
    required this.aisle,
    required this.bay,
    required this.level,
    required this.slot,
  });

  final String center;

  /// 구역 글자(온도대를 함께 뜻함)
  final String zone;

  /// 층(`5`·`6`·`7`, 지하 `B1`)
  final String floor;
  final String aisle;
  final String bay;
  final String level;
  final String slot;

  static final _re = RegExp(
    r'^([A-Z]+[0-9]+)-([A-H])-(B1|[0-9]{1,2})-([0-9]{2})-([0-9]{2})-([0-9])-([0-9])$',
  );

  static CdcLocationCode? parse(String code) {
    final m = _re.firstMatch(code.trim().toUpperCase());
    if (m == null) return null;
    return CdcLocationCode(
      center: m[1]!,
      zone: m[2]!,
      floor: m[3]!,
      aisle: m[4]!,
      bay: m[5]!,
      level: m[6]!,
      slot: m[7]!,
    );
  }

  int get _aisleNo => int.parse(aisle);

  /// 통로 90~92 — 랙이 아닌 자리(단 0·슬롯 1 로 채움)
  bool get isSpot => _aisleNo >= 90;
  bool get isShelf => _aisleNo >= 61 && _aisleNo <= 89;

  /// MFC 온도대 칩 색 글자(A 상온·C 냉장·F 냉동)로 — 색만 같은 것을 쓴다.
  String get tempLetter => switch (zone) {
    'A' => 'F',
    'B' => 'C',
    _ => 'A',
  };
}

String _tempText(AppLocalizations l10n, String zone) => switch (zone) {
  'A' => l10n.zoneFrozen,
  'B' => l10n.zoneChilled,
  _ => l10n.zoneAmbient,
};

String _kindText(AppLocalizations l10n, CdcLocationCode c) =>
    switch (int.parse(c.aisle)) {
      90 => l10n.cdcLocDock,
      91 => l10n.cdcLocStaging,
      92 => l10n.cdcLocLift,
      >= 61 => l10n.cdcLocShelf,
      _ => l10n.cdcLocRack,
    };

/// DC 위치 안내 — MFC [LocationGuide] 와 같은 배치(큰 제목 → 카드), 카드만 DC 코드에 맞춘다.
class CdcLocationGuide extends StatelessWidget {
  const CdcLocationGuide({
    super.key,
    required this.code,
    this.codeKey,
    this.title,
    this.detail,
  });

  final String code;
  final Key? codeKey;
  final String? title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title ?? l10n.locGoTo,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        if (detail case final d?)
          Text(
            d,
            style: theme.textTheme.bodyMedium?.copyWith(color: PdaColors.muted),
          ),
        const SizedBox(height: 12),
        CdcLocationCard(code: code, codeKey: codeKey),
      ],
    );
  }
}

/// DC 위치 카드 — 위에 온도대·구역·자리 종류 칩과 코드 원문, 아래 큰 조각:
/// 랙·선반은 층·통로·베이·단·칸, 접안·출고대기·승강기 문은 층·자리 번호.
class CdcLocationCard extends StatelessWidget {
  const CdcLocationCard({super.key, required this.code, this.codeKey});

  final String code;
  final Key? codeKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = CdcLocationCode.parse(code);
    final floor = c == null
        ? null
        : c.floor == 'B1'
        ? l10n.cdcLocBasement
        : c.floor;
    final tiles = c == null
        ? [(code, null)]
        : c.isSpot
        ? [(floor!, l10n.cdcLocFloor), (c.bay, l10n.cdcLocSpot)]
        : [
            (floor!, l10n.cdcLocFloor),
            (c.aisle, l10n.cdcLocAisle),
            (c.bay, l10n.cdcLocBay),
            (c.level, l10n.locLevel),
            (c.slot, l10n.locSlot),
          ];
    return Container(
      key: const ValueKey('cdc-location-card'),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PdaColors.lilac, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (c != null) ...[
                _Chip(
                  text: _tempText(l10n, c.zone),
                  color: tempChipColor(c.tempLetter),
                ),
                const SizedBox(width: 6),
                _Chip(text: l10n.cdcLocZone(c.zone), color: PdaColors.softer),
                const SizedBox(width: 6),
                _Chip(
                  text: _kindText(l10n, c),
                  color: c.isShelf ? PdaColors.lilac : PdaColors.soft,
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  code,
                  key: codeKey,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PdaColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ExcludeSemantics(
            child: Row(
              children: [
                for (final (i, (value, label)) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    // 층은 다른 칸보다 좁게(한 글자) — 통로·베이가 크게 보이게
                    flex: c != null && !c.isSpot && i == 0 ? 3 : 4,
                    child: Container(
                      key: ValueKey('cdc-loc-tile-$i'),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: PdaColors.softer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                value,
                                style: const TextStyle(
                                  color: PdaColors.primary,
                                  fontSize: 30,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                          if (label != null)
                            Text(
                              label,
                              style: const TextStyle(
                                color: PdaColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: PdaColors.dark,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
