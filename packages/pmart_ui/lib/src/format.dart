import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// 금액·시각 표시. 계산하지 않는다(합산·환불액은 서버 값을 그대로 쓴다).

/// 앱 시작·테스트 전에 한 번 부른다(한국어 날짜 기호 적재).
Future<void> initPmartFormatting() => initializeDateFormatting('ko');

final _krw = NumberFormat.decimalPattern('ko');

/// 정수 KRW → `12,300원`. [negative] 는 할인 표시처럼 화면이 부호를 붙일 때만 쓴다.
///
/// 계약 Money 는 음수가 없다. 음수가 오면 계약 위반이라 조용히 넘기지 않는다.
String formatKrw(int amount, {bool negative = false}) {
  if (amount < 0) {
    throw ArgumentError.value(amount, 'amount', 'Money 는 음수가 아니다');
  }
  return '${negative && amount > 0 ? '-' : ''}${_krw.format(amount)}원';
}

/// Asia/Seoul 은 UTC+9 고정(서머타임 없음). 시간대 DB 없이 변환한다.
const seoulOffset = Duration(hours: 9);

/// 서버 시각(UTC) → 서울 벽시계 시각. 반환값의 isUtc 는 true 지만 값은 서울 기준이다.
/// 표시 전용이다. 기한 판정에 쓰지 않는다.
DateTime toSeoulWallClock(DateTime instant) => instant.toUtc().add(seoulOffset);

/// `10월 24일 (토) 오후 4:05`
String formatSeoulDateTime(DateTime instant) =>
    DateFormat('M월 d일 (E) a h:mm', 'ko').format(toSeoulWallClock(instant));

/// `오후 4:05`
String formatSeoulTime(DateTime instant) =>
    DateFormat('a h:mm', 'ko').format(toSeoulWallClock(instant));

/// `11월 15일 (일)`
String formatSeoulDate(DateTime instant) =>
    DateFormat('M월 d일 (E)', 'ko').format(toSeoulWallClock(instant));

/// 한글 문장을 띄어쓰기에서만 줄바꿈되게 한다(글자 사이에 WORD JOINER U+2060).
/// Flutter 는 한글을 글자마다 끊어 "확인하세 / 요"처럼 끝 글자만 다음 줄로 넘기는 일이 있다 — 짧은 안내 문구에만 쓴다.
String keepWords(String text) => text
    .split(' ')
    .map((w) => w.runes.map(String.fromCharCode).join('⁠'))
    .join(' ');

/// 도착 슬롯 `오전 8:00~9:00`
String formatSeoulWindow(DateTime start, DateTime end) {
  final s = toSeoulWallClock(start);
  final e = toSeoulWallClock(end);
  final sameMeridiem = (s.hour < 12) == (e.hour < 12);
  final endText = sameMeridiem
      ? DateFormat('h:mm', 'ko').format(e)
      : DateFormat('a h:mm', 'ko').format(e);
  return '${DateFormat('a h:mm', 'ko').format(s)}~$endText';
}
