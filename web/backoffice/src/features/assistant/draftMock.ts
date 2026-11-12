// ⚠ 화면 개발·시험용 목. 실제 ai-assistant-service 동작이 아니다(서비스 LAN 미배포, BR-46 #13).
// - 계약 1.1.0 의 경로 의미(질의 200/202, answerId 다시 보기, 내 질문 목록)와 공통 규칙
//   (같은 Idempotency-Key·같은 본문 = 같은 결과, 같은 키·다른 본문 = 409 IDEMPOTENCY_CONFLICT, 403·404·422·503)만 흉내 낸다.
// - 응답 본문은 생성 타입(AnswerWire)으로 만들고 wire.ts 로 바꾼다 — 실서버 어댑터와 같은 길.
// - 질문 원문은 서버가 기본 저장하지 않는다(ADR-0036) → 목도 목록의 question 을 null 로 둔다.
import { tokens } from '../../api/client';
import type { IdempotencyKey } from '../../api/command';
import { type Problem, ProblemFailure, UnknownResultFailure } from '@pmart/web-core';
import { parseOperatorToken } from '@pmart/web-core';
import type { AssistantPort } from './port';
import { answerFromWire, historyFromWire, type AnswerWire, type HistoryWire } from './wire';

/** 목이 질문마다 고르는 결과. 화면 개발(dev 목 모드)은 질문의 꼬리표로, 테스트는 script 로 고른다. */
export type DraftScenario =
  | 'answer' // 근거 있는 답변(기준선 모드)
  | 'noGrounding' // 200 state=NO_GROUNDING
  | 'realtime' // 200 state=REALTIME_DATA_REQUIRED
  | 'outOfScope' // 200 state=OUT_OF_SCOPE
  | 'forbidden' // 403 Problem FORBIDDEN (운영자 아님 등)
  | 'configRequired' // 422 CONFIG_REQUIRED (색인 없음)
  | 'processingOnce' // 202 PROCESSING(첫 전송만). 같은 키 재전송이면 완료 답변
  | 'lostOnce' // 서버는 처리했는데 응답이 유실(첫 전송만). 같은 키 재전송이면 저장된 결과
  | 'unavailable'; // 503 DEPENDENCY_UNAVAILABLE (변경 요청이라 결과 불명으로 분류된다)

export interface DraftMockOptions {
  readonly script?: (question: string) => DraftScenario;
  readonly delayMs?: number;
  readonly now?: () => Date;
  /** 내 질문 목록 한 페이지 크기(계약 PageSize). */
  readonly pageSize?: number;
}

/** dev 목 모드 꼬리표. 화면 안내에 같은 목록을 보인다. */
export const DEV_TAGS: ReadonlyArray<readonly [string, DraftScenario]> = [
  ['#근거없음', 'noGrounding'],
  ['#실시간', 'realtime'],
  ['#실행요청', 'outOfScope'],
  ['#권한없음', 'forbidden'],
  ['#색인없음', 'configRequired'],
  ['#처리중', 'processingOnce'],
  ['#응답유실', 'lostOnce'],
  ['#장애', 'unavailable'],
];

export const tagScript = (question: string): DraftScenario => DEV_TAGS.find(([tag]) => question.includes(tag))?.[1] ?? 'answer';

function problem(status: number, code: string, retryable = false): ProblemFailure {
  const p: Problem = { status, code, type: 'about:blank', retryable, details: [], raw: { code } };
  return new ProblemFailure(p, `mock-${code.toLowerCase()}`);
}

const currentSubject = () => (tokens.accessToken ? (parseOperatorToken(tokens.accessToken)?.subject ?? null) : null);

const SNAPSHOT = 'IDX-MOCK-20261104-0700';
const AS_OF = { snapshotId: SNAPSHOT, sourceRevision: 'mock000', sourceDirty: false, indexedAt: '2026-11-04T07:00:00Z' };

interface Stored {
  readonly owner: string;
  readonly question: string;
  wire: AnswerWire;
  /** processingOnce: 첫 응답은 202, 그다음부터 완료. */
  pendingDone?: AnswerWire;
}

export interface DraftMock extends AssistantPort {
  /** 서버에 도착한 질의 수(중복 전송 확인용). 같은 키 재전송도 1건으로 센다. */
  readonly received: { key: string; question: string }[];
}

export function createDraftAssistantMock(options: DraftMockOptions = {}): DraftMock {
  const script = options.script ?? tagScript;
  const delay = options.delayMs ?? 0;
  const now = options.now ?? (() => new Date());
  const pageSize = options.pageSize ?? 20;
  const byKey = new Map<string, Stored>(); // Idempotency-Key → 처리 결과
  const byId = new Map<string, Stored>();
  const order: Stored[] = []; // 최근 순 목록용(앞이 최신)
  const lostOnce = new Set<string>(); // 이미 한 번 응답을 잃은 키
  const received: { key: string; question: string }[] = [];
  let seq = 0;

  const wait = () => (delay > 0 ? new Promise<void>((r) => setTimeout(r, delay)) : Promise.resolve());

  function compose(answerId: string, requestId: string, scenario: DraftScenario): AnswerWire {
    const base = { answerId, requestId, askedAt: now().toISOString(), indexSnapshotId: SNAPSHOT, citations: [] };
    if (scenario === 'noGrounding')
      return { ...base, state: 'NO_GROUNDING', answer: '허용된 문서에서 이 질문을 뒷받침할 근거를 찾지 못했습니다.', answerMode: 'NONE', retrievalMode: 'BASELINE_HASH' };
    if (scenario === 'realtime')
      return {
        ...base,
        indexSnapshotId: null,
        state: 'REALTIME_DATA_REQUIRED',
        answer: '특정 주문·재고·결제의 현재 상태는 이 기능으로 확인할 수 없습니다. 해당 업무 화면에서 조회하세요.',
        answerMode: 'NONE',
        retrievalMode: 'NONE',
      };
    if (scenario === 'outOfScope')
      return {
        ...base,
        indexSnapshotId: null,
        state: 'OUT_OF_SCOPE',
        answer: '환불·승인·재고 변경 같은 처리는 이 기능이 하지 않습니다. 해당 업무 화면에서 진행하세요.',
        answerMode: 'NONE',
        retrievalMode: 'NONE',
      };
    return {
      ...base,
      state: 'ANSWERED',
      answerMode: 'BASELINE_EXTRACTIVE',
      retrievalMode: 'BASELINE_HASH',
      // 목 답변 — 실제 정책 내용이 아니다. 서버 응답에 HTML 이 섞여 와도 화면은 텍스트로만 그린다.
      answer:
        '[목 답변] 질문하신 내용에 대해 아래 문서를 근거로 안내합니다.\n' +
        '1) 확정 정책은 근거 문서의 해당 절을 따릅니다.\n' +
        '2) 설계안·미결정 항목은 운영에 확정 값으로 쓰지 마세요.\n' +
        '<b>강조</b> 같은 표시는 해석하지 않습니다.',
      citations: [
        {
          chunkId: 'mock-chunk-1',
          documentId: 'docs/business/overview.md',
          path: 'docs/business/overview.md',
          section: '[목] 4. 확정 정책 > 4.9 반품',
          authority: 'CONFIRMED',
          lifecycleStatus: 'ACTIVE',
          supersededBy: null,
          proposedSupersededBy: [],
          implementationEvidence: null,
          documentVersion: 'v3',
          effectiveDate: '2026-10-23',
          asOf: AS_OF,
          excerpt: '[목 청크] 반품 접수 기한은 확정 정책 문서의 해당 절을 따른다.',
        },
        {
          chunkId: 'mock-chunk-2',
          documentId: 'docs/business/flows/cancel-vs-handover.md',
          path: 'docs/business/flows/cancel-vs-handover.md',
          section: '[목] S3 취소 접수 vs 인계 > 2. 흐름',
          authority: 'PROPOSAL',
          lifecycleStatus: 'SUPERSESSION_PROPOSED',
          supersededBy: null,
          proposedSupersededBy: ['docs/adr/0099-mock.md'],
          implementationEvidence: { recordDate: '2026-11-01', note: '[목] 1차 구현 기록' },
          documentVersion: null,
          effectiveDate: null,
          asOf: { ...AS_OF, sourceDirty: true },
          excerpt: '[목 청크] 설계안: 취소와 인계가 겹치면 …',
        },
        {
          chunkId: 'mock-chunk-3',
          documentId: 'docs/business/old-policy.md',
          path: 'docs/business/old-policy.md',
          section: null,
          authority: 'UNDECIDED',
          lifecycleStatus: 'SUPERSEDED',
          supersededBy: 'docs/adr/0036-mock.md',
          proposedSupersededBy: [],
          implementationEvidence: null,
          documentVersion: null,
          effectiveDate: null,
          asOf: AS_OF,
          excerpt: '[목 청크] 결정 필요: …',
        },
      ],
    };
  }

  const processing = (w: AnswerWire): AnswerWire => ({
    ...w,
    state: 'PROCESSING',
    answer: '',
    citations: [],
    answerMode: 'NONE',
    retrievalMode: 'NONE',
    indexSnapshotId: null,
  });

  /** 202 다음 조회부터는 완료로 바뀐다(목의 lease 끝). */
  function settle(s: Stored): AnswerWire {
    const out = s.wire;
    if (s.pendingDone) {
      s.wire = s.pendingDone;
      delete s.pendingDone;
    }
    return out;
  }

  return {
    connected: true,
    mock: true,
    mockHints: DEV_TAGS.map(([t]) => t),
    received,

    async ask(question: string, key: IdempotencyKey) {
      await wait();
      const owner = currentSubject();
      if (!owner) throw problem(401, 'UNAUTHORIZED');
      const saved = byKey.get(key.value);
      if (saved) {
        // 멱등 재생: 같은 키·같은 본문 = 같은 결과(새로 만들지 않는다)
        if (saved.question !== question || saved.owner !== owner) throw problem(409, 'IDEMPOTENCY_CONFLICT');
        return answerFromWire(settle(saved));
      }
      const scenario = script(question);
      if (scenario === 'forbidden') throw problem(403, 'FORBIDDEN');
      if (scenario === 'configRequired') throw problem(422, 'CONFIG_REQUIRED');
      if (scenario === 'unavailable') throw new UnknownResultFailure(problem(503, 'DEPENDENCY_UNAVAILABLE', true).problem, 'mock-unavailable');
      received.push({ key: key.value, question });
      seq += 1;
      const done = compose(`ans-mock-${seq}`, key.value, scenario);
      const stored: Stored =
        scenario === 'processingOnce' ? { owner, question, wire: processing(done), pendingDone: done } : { owner, question, wire: done };
      byKey.set(key.value, stored);
      byId.set(done.answerId, stored);
      order.unshift(stored);
      if (scenario === 'lostOnce' && !lostOnce.has(key.value)) {
        lostOnce.add(key.value);
        throw new UnknownResultFailure('mock: 응답 유실', 'mock-lost');
      }
      return answerFromWire(settle(stored));
    },

    async get(answerId: string) {
      await wait();
      const owner = currentSubject();
      const saved = byId.get(answerId);
      // 남의 답변은 있는지도 알리지 않는다
      if (!owner || !saved || saved.owner !== owner) throw problem(404, 'NOT_FOUND');
      return answerFromWire(settle(saved));
    },

    async history(cursor?: string) {
      await wait();
      const owner = currentSubject();
      if (!owner) throw problem(401, 'UNAUTHORIZED');
      const mine = order.filter((s) => s.owner === owner);
      const start = cursor ? Number(cursor) : 0;
      const slice = mine.slice(start, start + pageSize);
      const next = start + pageSize < mine.length ? String(start + pageSize) : null;
      const wire: HistoryWire = {
        items: slice.map(({ wire: w }) => ({
          answerId: w.answerId,
          requestId: w.requestId,
          state: w.state,
          question: null,
          answerPreview: w.state === 'PROCESSING' ? null : w.answer.slice(0, 120),
          answerMode: w.answerMode,
          citationCount: w.citations.length,
          askedAt: w.askedAt,
        })),
        page: { nextCursor: next, size: pageSize },
      };
      return historyFromWire(wire);
    },
  };
}
