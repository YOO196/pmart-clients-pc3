// 초안 계약(생성 타입) 응답 → 화면 모델. 목과 (계약 확정 뒤) 실서버 어댑터가 같이 쓴다.
// 초안 스키마는 필드가 모두 선택이다. 화면에 꼭 필요한 값(answerId·state)이 없으면 빈 값으로 메우지 않고 계약 위반으로 던진다.
import { ContractViolationFailure } from '../../api/failure';
import type { operations } from '../../api/generated/ai-assistant';
import { ANSWER_STATES, type AssistantAnswer, type Citation, type Grounding } from './model';

export type DraftAskResponse = operations['askPolicyQuestion']['responses'][200]['content']['application/json'];
export type DraftGetResponse = operations['getPolicyAnswer']['responses'][200]['content']['application/json'];
type DraftCitation = NonNullable<DraftAskResponse['citations']>[number];

/** BR-46 로 요청한 확장(초안 계약에 없음). 목만 채운다. */
export interface Br46CitationExtension {
  readonly title?: string;
  readonly section?: string;
  readonly docVersion?: string;
  readonly grounding?: Grounding;
}
export interface Br46AnswerExtension {
  readonly question?: string;
  readonly answeredAt?: string;
  /** 초안 POST 의 citations 에 BR-46 확장을 더한 모양. 초안 GET 에는 citations 가 없다 — BR-46 에서 같은 모양을 요청. */
  readonly citations?: ReadonlyArray<DraftCitation & Br46CitationExtension>;
}

export type AskWire = Omit<DraftAskResponse, 'citations'> & Br46AnswerExtension;
export type GetWire = DraftGetResponse & Br46AnswerExtension;

const GROUNDINGS: readonly Grounding[] = ['CONFIRMED_POLICY', 'DESIGN_PROPOSAL', 'UNDECIDED'];

function citationFrom(c: DraftCitation & Br46CitationExtension): Citation | null {
  if (typeof c.docRef !== 'string' || c.docRef.length === 0) return null; // 식별자 없는 출처는 출처로 보이지 않는다
  return {
    docRef: c.docRef,
    policyVersion: typeof c.policyVersion === 'number' ? c.policyVersion : null,
    ...(c.asOf?.asOf ? { asOf: c.asOf.asOf } : {}),
    ...(c.asOf?.freshness ? { freshness: c.asOf.freshness } : {}),
    ...(c.title ? { title: c.title } : {}),
    ...(c.section ? { section: c.section } : {}),
    ...(c.docVersion ? { docVersion: c.docVersion } : {}),
    ...(c.grounding && GROUNDINGS.includes(c.grounding) ? { grounding: c.grounding } : {}),
  };
}

export function answerFromWire(w: AskWire | GetWire, requestId?: string): AssistantAnswer {
  if (typeof w.answerId !== 'string' || w.answerId.length === 0) {
    throw new ContractViolationFailure('answerId 없음', requestId);
  }
  if (!w.state || !ANSWER_STATES.includes(w.state)) {
    throw new ContractViolationFailure(`state 값 이상: ${String(w.state)}`, requestId);
  }
  const citations = 'citations' in w && Array.isArray(w.citations) ? w.citations : undefined;
  return {
    answerId: w.answerId,
    state: w.state,
    answer: typeof w.answer === 'string' ? w.answer : '',
    citations: citations === undefined ? null : citations.map(citationFrom).filter((c): c is Citation => c !== null),
    ...(w.question ? { question: w.question } : {}),
    ...(w.answeredAt ? { answeredAt: w.answeredAt } : {}),
  };
}
