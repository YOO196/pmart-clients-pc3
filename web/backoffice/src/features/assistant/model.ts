// 업무 도우미(정책·업무 절차 질의응답) 화면 모델.
// 정본: contracts/openapi/ai-assistant-service.yaml — 3단계 "자리 표시용 초안"이다(BR-46). 서버 동작을 추측하지 않는다.
// 초안에 있는 값(answerId·state·answer·citations[].docRef·policyVersion·asOf)은 그대로 쓰고,
// 초안에 없는 값(질문 사본·절·문서 버전·확정/제안/미결정 구분·문서 제목)은 선택값으로만 두고 BR-46 으로 요청한다.

/** 초안 계약 state enum 그대로. */
export type AnswerState = 'ANSWERED' | 'NO_GROUNDING' | 'FORBIDDEN_SCOPE';
export const ANSWER_STATES: readonly AnswerState[] = ['ANSWERED', 'NO_GROUNDING', 'FORBIDDEN_SCOPE'];

/** 근거의 성격. BR-46 요청 값(초안 계약에 없음). 없으면 "구분 정보 없음"으로 보인다(추정하지 않는다). */
export type Grounding = 'CONFIRMED_POLICY' | 'DESIGN_PROPOSAL' | 'UNDECIDED';

export interface Citation {
  /** 백엔드가 검증한 문서 식별자. 링크로 만들지 않는다(문서 여는 방법은 BR-46). */
  readonly docRef: string;
  readonly policyVersion: number | null;
  readonly asOf?: string;
  readonly freshness?: 'CURRENT' | 'STALE' | 'UNAVAILABLE';
  // ---- BR-46 (초안 계약에 없음) ----
  readonly title?: string;
  readonly section?: string;
  readonly docVersion?: string;
  readonly grounding?: Grounding;
}

export interface AssistantAnswer {
  readonly answerId: string;
  readonly state: AnswerState;
  /** 모델 응답 원문. 신뢰할 수 없는 텍스트로 다룬다 — 일반 텍스트로만 그린다(HTML·마크다운 해석 없음). */
  readonly answer: string;
  /** null = 이 응답에 출처 목록이 오지 않음(초안 GET 은 citations 가 없다). 빈 배열 = 출처 0건. */
  readonly citations: readonly Citation[] | null;
  // ---- BR-46 ----
  readonly question?: string;
  readonly answeredAt?: string;
}

/** 서비스 상태(초안 계약 GET /actuator/health). 연결 안 됨은 별도. */
export type AssistantHealth = 'UP' | 'DOWN' | 'OUT_OF_SERVICE';

/**
 * 문서 식별자가 화면에 보여도 되는 모양인지. 서버 파일시스템 절대 경로·상위 경로·URL 은 보이지 않는다.
 * 백엔드가 검증한 식별자만 오는 것이 계약 요구이고(BR-46), 이 검사는 실수로 경로가 섞였을 때의 마지막 방어다.
 */
export function isDisplayableDocRef(docRef: string): boolean {
  const s = docRef.trim();
  if (s.length === 0 || s.length > 300) return false;
  if (/^[a-zA-Z]:[\\/]/.test(s)) return false; // C:\..., C:/...
  if (s.startsWith('/') || s.startsWith('\\') || s.startsWith('~')) return false;
  if (/^[a-z][a-z0-9+.-]*:/i.test(s)) return false; // file:, http:, javascript: ...
  if (s.split(/[\\/]/).includes('..')) return false;
  return true;
}
