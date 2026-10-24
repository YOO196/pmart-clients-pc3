import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

void main() {
  setUpAll(initPmartFormatting);

  test('금액은 천 단위 구분과 "원"으로 표시한다', () {
    expect(formatKrw(0), '0원');
    expect(formatKrw(12300), '12,300원');
    expect(formatKrw(3000, negative: true), '-3,000원');
    expect(formatKrw(0, negative: true), '0원');
  });

  test('음수 금액은 계약 위반이라 조용히 넘기지 않는다', () {
    expect(() => formatKrw(-1), throwsArgumentError);
  });

  test('UTC 를 서울 시각으로 표시한다(날짜가 넘어가는 경우 포함)', () {
    // 2026-10-24 15:30 UTC = 2026-10-25(일) 00:30 서울
    final t = DateTime.utc(2026, 10, 24, 15, 30);
    expect(formatSeoulDateTime(t), '10월 25일 (일) 오전 12:30');
    expect(formatSeoulTime(DateTime.utc(2026, 10, 24, 7, 5)), '오후 4:05');
  });

  test('도착 슬롯은 같은 오전/오후면 한 번만 쓴다', () {
    expect(
      formatSeoulWindow(
        DateTime.utc(2026, 10, 24, 23),
        DateTime.utc(2026, 10, 25, 0),
      ),
      '오전 8:00~9:00',
    );
    expect(
      formatSeoulWindow(
        DateTime.utc(2026, 10, 25, 2),
        DateTime.utc(2026, 10, 25, 3),
      ),
      '오전 11:00~오후 12:00',
    );
  });
}
