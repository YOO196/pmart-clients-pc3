import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/features/address/presentation/phone_number_formatter.dart';

void main() {
  group('format', () {
    String f(String s) => PhoneNumberFormatter.format(s);

    test('휴대폰 11자리 3-4-4, 10자리 3-3-4', () {
      expect(f('01012345678'), '010-1234-5678');
      expect(f('0111234567'), '011-123-4567');
    });

    test('서울 02 는 2-3-4 / 2-4-4', () {
      expect(f('021234567'), '02-123-4567');
      expect(f('0212345678'), '02-1234-5678');
    });

    test('지역번호 3-3-4 / 3-4-4', () {
      expect(f('0311234567'), '031-123-4567');
      expect(f('03112345678'), '031-1234-5678');
    });

    test('대표번호 4-4', () {
      expect(f('15881234'), '1588-1234');
    });

    test('입력하는 중에도 하이픈이 붙는다', () {
      expect(f('010'), '010');
      expect(f('0101'), '010-1');
      expect(f('0101234'), '010-1234');
      expect(f('0111234'), '011-123-4');
      expect(f('01012345'), '010-1234-5');
      expect(f('02'), '02');
      expect(f('021'), '02-1');
    });

    test('숫자 아닌 글자는 빼고 11자리까지만', () {
      expect(f('010-1234-5678'), '010-1234-5678');
      expect(f('010 1234 5678 9'), '010-1234-5678');
      expect(f('abc'), '');
    });
  });

  testWidgets('칸에 치면 하이픈이 붙고, 하이픈 뒤에서 지우면 앞 숫자가 지워진다', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: c,
            inputFormatters: const [PhoneNumberFormatter()],
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextField), '01012345678');
    expect(c.text, '010-1234-5678');
    expect(c.selection.baseOffset, c.text.length);

    // "010-|1234" 에서 지우기 → 하이픈만 빠진 값이 들어온다.
    const before = TextEditingValue(
      text: '010-1234-5678',
      selection: TextSelection.collapsed(offset: 4),
    );
    final after = const PhoneNumberFormatter().formatEditUpdate(
      before,
      const TextEditingValue(
        text: '0101234-5678',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(after.text, '011-234-5678');
    expect(after.selection.baseOffset, 2);
  });
}
