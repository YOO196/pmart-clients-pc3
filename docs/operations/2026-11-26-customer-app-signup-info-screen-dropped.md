# 고객앱 가입 때 소셜 로그인을 두 번 눌러야 하던 문제 — 2026-11-26

- 누가: PC1 프론트(사용자 "처음 소셜로그인으로 가입할 때 한 번 더 눌러야" → "방금 에러사항 문서로 정리해줘")
- 고친 커밋: `d059faf3`(원본 main) — `apps/customer_app/lib/features/auth/presentation/login_screen.dart` `_waitStartSettled`
- 확인: 실기기(R5CT30GWPWM) 네이버 새 가입이 한 번에 끝남(동의 → 휴대폰 확인 → 내 정보 등록 → 저장), 시험 `test/login_identity_test.dart` "새 가입: 동의 → 휴대폰 확인 → 바로 내 정보 등록" 추가, 로그인·가입·프로필 시험 120개 통과

## 증상
- **처음 가입하는 계정만**, 모든 소셜(카카오·네이버·구글) 공통.
- 소셜 동의 → 앱 약관 동의 → 휴대폰 확인까지 마치면 "내 정보 등록"이 떠야 하는데, 로그인 버튼 화면이 그대로 남는다.
- 버튼을 한 번 더 누르면 이미 가입된 계정이라 바로 로그인되고 화면이 닫힌다. 그래서 "두 번 눌러야 로그인된다"로 보였다.
- 기존 회원 로그인, 목(mock) 시험에서는 생기지 않았다.

## 찾은 방법
1. 코드만으로는 원인을 확정하지 못해 로그인 흐름 단계마다 `debugPrint('[PM-LOGIN] …')` 를 임시로 넣었다.
   - 넣은 곳: 흐름 시작·제공자 토큰 받음·결과(_settle)·화면 상태·흐름 정리(dispose), 가입 뒤 처리(_afterLogin), 라우터 redirect, 처음 단계(startStep) 변화.
   - 토큰·전화번호·이름 같은 값은 남기지 않고 상태 이름만 남겼다.
2. profile 빌드를 폰에 설치하고 `adb logcat -s flutter:I | grep PM-LOGIN` 을 지켜보는 동안 사용자가 탈퇴 → 새 가입을 했다.
3. 첫 기록:

   ```
   settle LoginMember            ← 가입 완료(회원)
   afterLogin new=true loc=/login ← "내 정보 등록" push 시작
   (info closed 기록 없음)         ← push 한 화면이 끝내 닫힌 적이 없다 = 처음부터 안 들어갔다
   screen state=LoginWorking      ← 사용자가 로그인 버튼을 다시 누름
   settle LoginMember / afterLogin new=false → pop
   ```

   push 한 "내 정보 등록"이 화면 목록에 들어가지 않았고, 로그인 화면이 맨 위에 남았다.
4. 두 번째 기록(처음 단계 변화 기록 추가):

   ```
   afterLogin new=true
   startStep StartStep.loading
   startStep StartStep.ready
   info closed result=true        ← 고친 뒤: 내 정보 등록이 뜨고 저장됨
   ```

## 원인
- 회원이 되는 순간(`sessionProvider` 가 회원으로 바뀜) 앱 전체가 다시 계산된다.
  - `app.dart` 의 세션 듣기: 처음 단계 완료(`completeEntry`), 비회원 주소·장바구니 옮기기.
  - `startStepProvider`: 회원 주소록(`addressBookProvider`)을 새로 읽는 동안 `loading`, 다 읽으면 `ready`.
- 라우터(`router.dart`)는 `refreshListenable: startStep` 이라 처음 단계가 바뀔 때마다 redirect 를 다시 보고 **지금 화면 목록을 다시 맞춘다**.
- 가입 뒤 처리(`_afterLogin`)가 바로 이 사이(loading → ready)에 `context.push('/me/info?from=signup')` 를 했다. 라우터가 목록을 다시 맞추면서 아직 확정되지 않은 그 push 가 빠졌다.
  - 오류도 없고, push 의 Future 도 끝나지 않는다.
- 목 시험에서는 주소록·세션이 바로 끝나 이 사이가 거의 없어 드러나지 않았다. 실서버는 주소록 조회가 수백 ms 걸려 매번 걸렸다.
- 덧붙여 그 첫 기록에서는 첫 누름이 제공자 쪽 "취소"(토큰 없음)로 돌아온 적도 있었다. 두 번째 시도에서는 첫 누름에 바로 동의 화면으로 가서, 사용자가 닫은 것으로 본다(따로 생기면 그때 다시 본다).

## 고침
- `_afterLogin` 에서 새 계정이면 `_waitStartSettled()` 로 처음 단계가 `ready` 가 될 때까지(최대 5초) 기다리고, 프레임 두 번을 넘긴 뒤 "내 정보 등록"을 연다.
- 진단용 `[PM-LOGIN]` 기록은 모두 뺐다.

## 같은 위험이 있는 곳(아직 손대지 않음)
- **로그인·가입 직후 곧바로 `push` 하는 곳은 모두 같은 위험이 있다.** 회원이 되면 처음 단계가 다시 정해지기 때문이다.
  - 장바구니 [주문하기] 로그인 뒤 병합 화면: `cart_screen.dart` 의 `router.push('/cart/merge')`.
  - 새 계정이면 주소록이 비어 처음 단계가 `address` 로 갈 수도 있다.
- 같은 증상(화면이 안 뜨고 다시 눌러야 함)이 보이면 이 문서의 방법으로 기록을 남겨 확인하고, `_waitStartSettled` 와 같은 방식으로 고친다.
- 근본적으로는 "로그인 뒤 열 화면"을 라우터 redirect 나 처음 단계 쪽에서 정하는 편이 안전하다. 지금은 화면마다 따로 push 한다.

## 다음에 진단할 때
- profile 빌드에도 `debugPrint` 는 logcat(`flutter` 태그)에 나온다. 값(토큰·번호·이름)은 절대 찍지 않고 상태 이름만 찍는다.
- 확인 명령: `adb -s <기기> logcat -c` 로 비운 뒤 `adb -s <기기> logcat -v brief -s flutter:I | grep <머리말>`.
- 원인을 찾으면 진단 줄을 빼고 커밋한다(이번 커밋에는 남기지 않았다).
