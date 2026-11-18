import 'package:flutter/foundation.dart';

/// 찍은 LOT 라벨 값(mfc-inventory 0.21.0 — GS1-128 `(01)GTIN-14(17)YYMMDD(10)lotNo`, 예전 QR `LOT:{lotId}`).
///
/// 서버 호출 없이 피킹 지시(`picks[].lotNo`·`lotId`)와 대조할 때 쓴다(계약 "피킹은 picks[].lotNo 로 바로 대조해도 된다").
/// 다른 화면에서 LOT 을 확정하려면 `GET /mfcs/{id}/lot-resolutions?code=` 로 서버에 묻는다.
@immutable
class LotCode {
  const LotCode({this.lotId, this.lotNo, this.gtin, this.expiry});

  /// 예전 QR `LOT:{lotId}`.
  final String? lotId;

  /// GS1 (10).
  final String? lotNo;

  /// GS1 (01) GTIN-14.
  final String? gtin;

  /// GS1 (17) YYMMDD.
  final String? expiry;

  /// [barcode](상품 바코드 8·12·13·14자리)를 GTIN-14 로 맞춰 (01) 과 같은지. (01) 이 없으면 null(모름).
  bool? sameProduct(Iterable<String> barcodes) {
    final g = gtin;
    if (g == null) return null;
    return barcodes.any(
      (b) => RegExp(r'^\d{8,14}$').hasMatch(b) && b.padLeft(14, '0') == g,
    );
  }
}

const _gs = '\u001d';

/// AI → 고정 길이(가변이면 null). 계약이 읽는 AI 만(01·10·11·15·17·21).
const _fixed = {'01': 14, '11': 6, '15': 6, '17': 6};
const _variable = {'10', '21'};

/// LOT 라벨이 아니면 null(상품 바코드·칸·장바구니 등).
LotCode? parseLotCode(String raw) {
  var c = raw.trim();
  if (c.startsWith('LOT:')) {
    final id = c.substring(4).trim();
    return id.isEmpty ? null : LotCode(lotId: id);
  }
  if (c.startsWith(']C1')) c = c.substring(3);
  final ais = c.startsWith('(') ? _parseBracketed(c) : _parseRaw(c);
  if (ais == null || ais['10'] == null) return null;
  return LotCode(lotNo: ais['10'], gtin: ais['01'], expiry: ais['17']);
}

/// `(01)08801234567890(17)261231(10)L261117001`.
Map<String, String>? _parseBracketed(String c) {
  final out = <String, String>{};
  final re = RegExp(r'\((\d{2})\)([^()]*)');
  var pos = 0;
  for (final m in re.allMatches(c)) {
    if (m.start != pos) return null;
    out[m.group(1)!] = m.group(2)!;
    pos = m.end;
  }
  return pos == c.length && out.isNotEmpty ? out : null;
}

/// 스캐너 원문: AI 가 바로 이어지고, 가변 길이 값 뒤에는 GS.
Map<String, String>? _parseRaw(String c) {
  final out = <String, String>{};
  var i = 0;
  while (i < c.length) {
    if (c[i] == _gs) {
      i++;
      continue;
    }
    if (i + 2 > c.length) return null;
    final ai = c.substring(i, i + 2);
    i += 2;
    final n = _fixed[ai];
    if (n != null) {
      if (i + n > c.length) return null;
      out[ai] = c.substring(i, i + n);
      i += n;
    } else if (_variable.contains(ai)) {
      final end = c.indexOf(_gs, i);
      out[ai] = c.substring(i, end < 0 ? c.length : end);
      i = end < 0 ? c.length : end + 1;
    } else {
      return null;
    }
  }
  // 숫자만인 상품 바코드(880…)가 우연히 AI 처럼 읽히지 않게 (01)+(10) 꼴만 받는다.
  return out.containsKey('01') && out.containsKey('10') ? out : null;
}
