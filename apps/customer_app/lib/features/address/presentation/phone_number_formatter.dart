import 'package:flutter/services.dart';

/// 연락처 입력을 전화번호 모양(하이픈)으로 바꾼다. 숫자만 받고 최대 11자리.
/// - 010: 3-4-4 (010-1234-5678). 011·016~019·지역번호(031 …): 3-3-4 / 3-4-4
/// - 서울(02): 2-3-4 / 2-4-4 (02-123-4567)
/// - 대표번호(15xx·16xx·18xx): 4-4 (1588-1234)
/// 서버는 하이픈을 무시하고 숫자로 비교한다(계약 receiverPhone, maxLength 20).
final class PhoneNumberFormatter extends TextInputFormatter {
  const PhoneNumberFormatter();

  static const maxDigits = 11;

  static String format(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length > maxDigits) d = d.substring(0, maxDigits);
    String join(List<int> sizes) {
      final parts = <String>[];
      var i = 0;
      for (final (n, size) in sizes.indexed) {
        if (i >= d.length) break;
        final last = n == sizes.length - 1;
        final end = last ? d.length : (i + size).clamp(0, d.length);
        parts.add(d.substring(i, end));
        i = end;
      }
      return parts.join('-');
    }

    if (d.startsWith('02')) {
      // 02-123-4567(9자리) / 02-1234-5678(10자리)
      return join([2, d.length >= 10 ? 4 : 3, 4]);
    }
    if (RegExp(r'^1[5-9]\d{2}').hasMatch(d) && d.length <= 8) {
      return join([4, 4]);
    }
    // 010 은 늘 11자리라 처음부터 3-4-4 로 붙인다(입력 중 모양이 바뀌지 않게).
    if (d.startsWith('010')) return join([3, 4, 4]);
    // 011·016~019·지역번호: 011-123-4567(10자리) / 031-1234-5678(11자리)
    return join([3, d.length >= 11 ? 4 : 3, 4]);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var edited = newValue;
    final cursor0 = newValue.selection.end.clamp(0, newValue.text.length);
    // 하이픈만 지운 지우기(숫자는 그대로)면 그 앞 숫자를 지운다 — 안 그러면 하이픈이 다시 붙어 지워지지 않는다.
    String digits(String s) => s.replaceAll(RegExp(r'\D'), '');
    if (newValue.text.length < oldValue.text.length &&
        digits(newValue.text) == digits(oldValue.text) &&
        cursor0 > 0) {
      final t = newValue.text;
      edited = TextEditingValue(
        text: t.substring(0, cursor0 - 1) + t.substring(cursor0),
        selection: TextSelection.collapsed(offset: cursor0 - 1),
      );
    }
    // 커서 앞 숫자 개수를 지켜 포맷 뒤 같은 숫자 뒤에 커서를 둔다.
    final cursor = edited.selection.end.clamp(0, edited.text.length);
    final digitsBefore = digits(edited.text.substring(0, cursor)).length;
    final text = format(edited.text);
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < digitsBefore) {
      if (RegExp(r'\d').hasMatch(text[offset])) seen++;
      offset++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
