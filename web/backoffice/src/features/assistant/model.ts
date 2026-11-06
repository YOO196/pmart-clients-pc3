// 업무 도우미(정책·업무 절차 질의응답) 화면 모델.
// 정본: contracts/openapi/ai-assistant-service.yaml 1.1.0(ADR-0036, BR-46 회신 2026-11-04). 서버 값을 그대로 보이고 지어내지 않는다.
// 인용의 지위(authority)·생애(lifecycleStatus)·구현 기록(implementationEvidence)은 서로 다른 축이라 따로 보인다.

/** 계약 AnswerState 그대로. PROCESSING 은 202(처리 중)에서만 온다. */
export type AnswerState = 'ANSWERED' | 'NO_GROUNDING' | 'REALTIME_DATA_REQUIRED' | 'OUT_OF_SCOPE' | 'FORBIDDEN_SCOPE' | 'PROCESSING';
export const ANSWER_STATES: readonly AnswerState[] = [
  'ANSWERED',
  'NO_GROUNDING',
  'REALTIME_DATA_REQUIRED',
  'OUT_OF_SCOPE',
  'FORBIDDEN_SCOPE',
  'PROCESSING',
];

export type AnswerMode = 'GENERATIVE' | 'BASELINE_EXTRACTIVE' | 'NONE';
export const ANSWER_MODES: readonly AnswerMode[] = ['GENERATIVE', 'BASELINE_EXTRACTIVE', 'NONE'];
export type RetrievalMode = 'SEMANTIC' | 'BASELINE_HASH' | 'NONE';
export const RETRIEVAL_MODES: readonly RetrievalMode[] = ['SEMANTIC', 'BASELINE_HASH', 'NONE'];

/** 근거의 정책 지위. */
export type Authority = 'CONFIRMED' | 'ADOPTED_DESIGN' | 'PROPOSAL' | 'ASSUMPTION' | 'UNDECIDED' | 'EXTERNAL_REFERENCE';
export const AUTHORITIES: readonly Authority[] = ['CONFIRMED', 'ADOPTED_DESIGN', 'PROPOSAL', 'ASSUMPTION', 'UNDECIDED', 'EXTERNAL_REFERENCE'];

export type LifecycleStatus = 'ACTIVE' | 'SUPERSEDED' | 'SUPERSESSION_PROPOSED' | 'EXCLUDED_FROM_PHASE1';
export const LIFECYCLE_STATUSES: readonly LifecycleStatus[] = ['ACTIVE', 'SUPERSEDED', 'SUPERSESSION_PROPOSED', 'EXCLUDED_FROM_PHASE1'];

export interface Citation {
  readonly chunkId: string;
  readonly documentId: string;
  /** 저장소 상대 경로. 링크로 만들지 않는다(1차에 문서 열람 API 없음). */
  readonly path: string;
  readonly section: string | null;
  readonly authority: Authority;
  readonly lifecycleStatus: LifecycleStatus;
  readonly supersededBy: string | null;
  readonly proposedSupersededBy: readonly string[];
  /** 날짜가 붙은 구현 기록 절일 때만. 그 날짜 기준 기록이고 현재 구현을 보장하지 않는다. */
  readonly implementationEvidence: { readonly recordDate: string; readonly note: string | null } | null;
  readonly documentVersion: string | null;
  readonly effectiveDate: string | null;
  readonly asOf: {
    readonly snapshotId: string;
    readonly sourceRevision: string | null;
    readonly sourceDirty: boolean;
    readonly indexedAt: string;
  };
  /** 근거 청크 본문 전문. 신뢰할 수 없는 텍스트 — 일반 텍스트로만 그린다. */
  readonly excerpt: string;
}

export interface AssistantAnswer {
  readonly answerId: string;
  /** 질의 때의 Idempotency-Key. */
  readonly requestId: string;
  readonly state: AnswerState;
  /** 서버 응답 원문. 신뢰할 수 없는 텍스트로 다룬다 — 일반 텍스트로만 그린다(HTML·마크다운 해석 없음). */
  readonly answer: string;
  readonly citations: readonly Citation[];
  readonly answerMode: AnswerMode;
  readonly retrievalMode: RetrievalMode;
  readonly indexSnapshotId: string | null;
  readonly askedAt: string;
}

/** 내 질문 목록 한 줄. 질문 원문은 기본 저장하지 않아 question 은 대개 null — answerPreview 로 구분한다. */
export interface HistoryItem {
  readonly answerId: string;
  readonly requestId: string;
  readonly state: AnswerState;
  readonly question: string | null;
  readonly answerPreview: string | null;
  readonly citationCount: number | null;
  readonly askedAt: string;
}

export interface HistoryPage {
  readonly items: readonly HistoryItem[];
  readonly nextCursor: string | null;
}

/** 기준선(외부 모델 없음) — 파이프라인은 검증됐지만 의미 검색·생성 품질은 검증되지 않았다. */
export const isBaseline = (a: Pick<AssistantAnswer, 'answerMode' | 'retrievalMode'>): boolean =>
  a.answerMode === 'BASELINE_EXTRACTIVE' || a.retrievalMode === 'BASELINE_HASH';

/**
 * 인용 경로가 화면에 보여도 되는 모양인지(계약: 저장소 상대 경로). 서버 파일시스템 절대 경로·상위 경로·URL 은 보이지 않는다.
 * 서버가 청크 메타데이터로 만드는 것이 계약이고, 이 검사는 실수로 다른 경로가 섞였을 때의 마지막 방어다.
 */
export function isDisplayablePath(path: string): boolean {
  const s = path.trim();
  if (s.length === 0 || s.length > 300) return false;
  if (/^[a-zA-Z]:[\\/]/.test(s)) return false; // C:\..., C:/...
  if (s.startsWith('/') || s.startsWith('\\') || s.startsWith('~')) return false;
  if (/^[a-z][a-z0-9+.-]*:/i.test(s)) return false; // file:, http:, javascript: ...
  if (s.split(/[\\/]/).includes('..')) return false;
  return true;
}
