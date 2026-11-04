# [pmart-clients → pmart-backend] 백오피스 "업무 도우미"(정책·업무 절차 RAG) 계약 확정 요청 (BR-46) (2026-11-04)

- 관련: `contracts/openapi/ai-assistant-service.yaml`(x-stage 3, "자리 표시용 초안", 2c39a4d 이후 변경 없음), `_common.yaml`(IdempotencyKey·SourceSystem·AsOf·Problem), 게이트웨이 `api-gateway.yml`(ai-assistant 라우트 없음). 읽은 백엔드 HEAD `4342c58`.
- 클라이언트 현황(2026-11-04): React 백오피스에만 화면을 만들었다(`/assistant`, `/assistant/answers/:answerId`). **실서버에는 연결하지 않았다** — local·LAN 빌드는 "아직 연결되지 않았어요" 안내만 보이고 호출하지 않는다. 화면 확인은 목 모드에서만 하고, 목은 "계약 확정 전(BR-46)"이라고 화면에 표시한다. 고객·라이더·MFC 앱에는 넣지 않는다.
- 범위(사용자 지시): 정책·업무 절차 질의응답만. 주문·재고·환불·승인 변경 버튼이나 AI 자동 실행은 만들지 않는다.

## 1. 초안 계약으로 화면에 필요한 것을 표현할 수 없는 부분

| # | 화면 요구 | 초안 계약 | 요청 |
|---|---|---|---|
| 1 | 근거 문서의 **절·문서 버전·기준 시점** | `citations[]` = `docRef`·`policyVersion`·`asOf` 만 | `section`(절 식별/제목), `docVersion`(문서 개정), `title`(표시 이름) 추가. `asOf` 는 지금 모양 유지 |
| 2 | **확정 정책 / 설계 제안 / 미결정** 구분 | 없음 | 출처마다(필요하면 답변 전체에도) 구분 값. 예 `grounding: CONFIRMED_POLICY \| DESIGN_PROPOSAL \| UNDECIDED`. 업무 문서 우선순위(domain-map §3)와 같은 기준으로 서버가 정함 |
| 3 | 출처는 **백엔드가 검증한 문서 식별자** | `docRef: string`(형식 설명 없음) | `docRef` 가 검증된 식별자임을 명시하고 형식(예: 문서 ID + 절 ID)을 정해 달라. 서버 파일시스템 경로·내부 URL 을 넣지 않음을 계약에 적어 달라 |
| 4 | **근거 문서를 여는 방법** | 없음 | 운영자가 원문을 볼 수 있어야 하면 경로를 정해 달라(예: `GET /assistant/documents/{docRef}`·절 앵커, 또는 "열람 없음"). 정해질 때까지 화면은 식별자만 글자로 보이고 링크를 만들지 않는다 |
| 5 | **기존 답변 조회** — 출처 포함 | `GET /assistant/policy-questions/{answerId}` 응답에 `citations` 없음 | 질의 응답과 같은 모양(citations·질문 사본·답변 시각)으로 |
| 6 | 이전 질문 **목록** | 없음 | 본인 질문·답변 목록(최근 순·커서). 없으면 화면은 이번 화면에서 받은 답변만 메모리로 보인다(새로고침·로그아웃 시 사라짐) |
| 7 | **응답 유실 뒤 복구** | 질의는 동기 200 만. 짝 조회는 `answerId` 가 있어야 함 | 응답을 못 받으면 `answerId` 를 모른다. ① 같은 `Idempotency-Key`·같은 본문 재전송이 저장된 결과(같은 `answerId`)를 돌려준다는 것을 이 경로에도 명시해 달라(지금 화면은 이 규칙에만 기댄다), ② 가능하면 키로 찾는 짝 조회(예: `GET /assistant/policy-questions?requestId=`) |
| 8 | **결과 확인 중**(생성이 오래 걸림) | 동기 200, `ACCEPTED`·진행 상태 없음 | 답변 생성이 길면 `202 + answerId` 와 진행 상태(예: `state: PENDING`)·권장 폴링 간격을 정해 달라. 동기로 간다면 서버 응답 시간 상한(타임아웃)을 알려 달라 |
| 9 | **서비스 장애** 구분 | `/actuator/health` 만(게이트웨이 경유 여부 불명) | 장애 시 질의 응답(예: 503 `DEPENDENCY_UNAVAILABLE`, `retryable`)과, 화면이 쓸 상태 확인 경로(게이트웨이 공개 여부)를 정해 달라 |
| 10 | **권한** | 403 + `state: FORBIDDEN_SCOPE` | 어떤 역할이 쓸 수 있는지, 403(사용 불가)과 `FORBIDDEN_SCOPE`(이 질문의 문서 범위 밖)의 구분 기준. 화면은 메뉴를 숨기지 않고 서버 판정만 보인다 |
| 11 | 질문 `context` | `additionalProperties: true` | 화면이 보낼 값이 있으면 키를 정해 달라. 정해질 때까지 보내지 않는다 |
| 12 | 응답 필수 필드 | 모든 필드가 선택 | 최소 `answerId`·`state` 를 required 로. 화면은 없으면 계약 위반으로 오류 처리한다(빈 값으로 메우지 않음) |
| 13 | 게이트웨이 라우트 | `/api/v1/assistant/**` 라우트 없음 | 확정 시 라우트·인증(운영자 토큰) 추가 |
| 14 | 답변 본문 형식 | `answer: string` | 일반 텍스트인지(화면은 지금 일반 텍스트로만 그린다, HTML·마크다운 해석 없음). 서식이 필요하면 허용 형식을 정해 달라 |

## 2. 화면이 지키는 규칙 (계약에 반영해 주면 좋은 것)
- 질의 = 변경 요청처럼 `Idempotency-Key`·`X-Source-System: backoffice-web` 를 붙인다. 새 전송은 새 키, 결과 불명(타임아웃·5xx·`DEPENDENCY_UNAVAILABLE`·응답 유실)은 실패로 단정하지 않고 **같은 키·같은 질문**으로만 다시 보낸다.
- `NO_GROUNDING` 은 "근거 문서를 찾지 못했어요"로, 조회·서버 오류는 오류로 보인다(서로 바꾸지 않는다).
- 계정이 바뀌거나 로그아웃하면 이전 사용자의 질문·답변 화면 상태와 캐시를 지운다. 남의 `answerId` 조회는 404 로 오길 기대한다(목도 그렇게 동작).
- 모델 응답은 신뢰할 수 없는 텍스트로 다룬다.

## 3. 확정 뒤 클라이언트 작업
- 계약 재생성(`npm run gen:api`) → 생성 클라이언트 + 공통 `pmartFetch`(인증·헤더)·`request()`(실패 분류)로 어댑터를 만들어 `AssistantPort` 에 끼운다. 화면·테스트는 그대로 두고, 목을 확정 계약에 맞춘다.
- 실서버 확인은 LAN 에서 따로 보고한다.
