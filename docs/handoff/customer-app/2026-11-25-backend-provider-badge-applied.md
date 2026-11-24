# 회신 — 마이 화면 가입 방식 배지 반영

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-request-provider-badge-next-to-email.md`
- 상태: 반영(목 모드·시험). 백엔드 변경 없음. 실기기 확인 대기.

## 반영
- R1 마이 화면 계정 줄 이메일 옆에 가입 방식 배지(카카오 노랑·네이버 초록·구글 흰 바탕 파랑 글자·애플 검정 — 로그인 단추 색). 값은 `GET /me` `socialProvider` 먼저, 없으면 이 기기 세션 제공자, 둘 다 없으면 배지 없음. 새 위젯 `lib/features/auth/presentation/provider_badge.dart`.
- R2 위 줄 "○○로 로그인했어요" 도 같은 값(`profile.socialProvider ?? session.provider`) — 앱을 다시 켜 복원한 세션에서도 제공자가 보인다(프로필을 읽은 뒤).
- 내 정보 화면 로그인 계정 칸도 같은 배지로(전에는 글자만).
- 이메일은 그대로(제공자가 준 연락처 이메일).

## 확인
- 시험 `test/profile_google_test.dart` "가입 방식은 서버 프로필(socialProvider) 먼저 …" — 카카오로 로그인한 세션 + 프로필 socialProvider NAVER·gmail 이메일 → 배지 "네이버", "네이버로 로그인했어요", 내 정보 배지 "네이버". 마이·로그인·프로필 시험 65 통과.
