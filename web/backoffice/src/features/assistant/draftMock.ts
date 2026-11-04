// ⚠ 계약 확정 전 화면용 목(BR-46). 실제 ai-assistant-service 동작이 아니다.
// - 초안 계약의 경로 의미(질의 → answerId·state·citations, answerId 짝 조회, health)와 공통 규칙
//   (같은 Idempotency-Key·같은 본문 = 같은 결과, 같은 키·다른 본문 = 409 IDEMPOTENCY_CONFLICT, 403 Problem)만 흉내 낸다.
// - 초안에 없는 값(질문 사본·절·문서 버전·확정/제안/미결정·GET 의 citations)은 BR-46 확장으로만 채운다.
// - 응답 본문은 생성 타입(초안 계약) + BR-46 확장 타입으로 만들고 wire.ts 로 바꾼다 — 실서버 어댑터와 같은 길.
import { tokens } from '../../api/client';
import type { IdempotencyKey } from '../../api/command';
import { type Problem, ProblemFailure, UnknownResultFailure } from '../../api/failure';
import { parseOperatorToken } from '../../api/session';
import type { AssistantHealth } from './model';
import type { AssistantPort } from './port';
import { answerFromWire, type AskWire } from './wire';

/** 목이 질문마다 고르는 결과. 화면 개발(dev 목 모드)은 질문의 꼬리표로, 테스트는 script 로 고른다. */
export type DraftScenario =
  | 'answer' // 근거 있는 답변
  | 'noGrounding' // 200 state=NO_GROUNDING
  | 'forbiddenScope' // 200 state=FORBIDDEN_SCOPE
  | 'forbidden' // 403 Problem FORBIDDEN (운영자 아님 등)
  | 'lostOnce' // 서버는 처리했는데 응답이 유실(첫 전송만). 같은 키 재전송이면 저장된 결과
  | 'unavailable'; // 503 DEPENDENCY_UNAVAILABLE (변경 요청이라 결과 불명으로 분류된다)

export interface DraftMockOptions {
  readonly script?: (question: string) => DraftScenario;
  readonly delayMs?: number;
  readonly health?: () => AssistantHealth;
  readonly now?: () => Date;
}

/** dev 목 모드 꼬리표. 화면 안내에 같은 목록을 보인다. */
export const DEV_TAGS: ReadonlyArray<readonly [string, DraftScenario]> = [
  ['#근거없음', 'noGrounding'],
  ['#범위밖', 'forbiddenScope'],
  ['#권한없음', 'forbidden'],
  ['#응답유실', 'lostOnce'],
  ['#장애', 'unavailable'],
];

export const tagScript = (question: string): DraftScenario => DEV_TAGS.find(([tag]) => question.includes(tag))?.[1] ?? 'answer';

function problem(status: number, code: string, retryable = false): ProblemFailure {
  const p: Problem = { status, code, type: 'about:blank', retryable, details: [], raw: { code } };
  return new ProblemFailure(p, `mock-${code.toLowerCase()}`);
}

const currentSubject = () => (tokens.accessToken ? (parseOperatorToken(tokens.accessToken)?.subject ?? null) : null);

interface Stored {
  readonly owner: string;
  readonly question: string;
  readonly wire: AskWire;
}

export interface DraftMock extends AssistantPort {
  /** 서버에 도착한 질의 수(중복 전송 확인용). 같은 키 재전송도 1건으로 센다. */
  readonly received: { key: string; question: string }[];
}

export function createDraftAssistantMock(options: DraftMockOptions = {}): DraftMock {
  const script = options.script ?? tagScript;
  const delay = options.delayMs ?? 0;
  const now = options.now ?? (() => new Date());
  const byKey = new Map<string, Stored>(); // Idempotency-Key → 처리 결과
  const byId = new Map<string, Stored>();
  const lostOnce = new Set<string>(); // 이미 한 번 응답을 잃은 키
  const received: { key: string; question: string }[] = [];
  let seq = 0;

  const wait = () => (delay > 0 ? new Promise<void>((r) => setTimeout(r, delay)) : Promise.resolve());

  function compose(question: string, scenario: DraftScenario): AskWire {
    seq += 1;
    const answerId = `ans-mock-${seq}`;
    const answeredAt = now().toISOString();
    const base = { answerId, question, answeredAt };
    if (scenario === 'noGrounding') return { ...base, state: 'NO_GROUNDING', answer: '', citations: [] };
    if (scenario === 'forbiddenScope') return { ...base, state: 'FORBIDDEN_SCOPE', answer: '', citations: [] };
    return {
      ...base,
      state: 'ANSWERED',
      // 목 답변 — 실제 정책 내용이 아니다. 모델 응답처럼 HTML 이 섞여 와도 화면은 텍스트로만 그린다.
      answer:
        '[목 답변] 질문하신 내용에 대해 아래 문서를 근거로 안내합니다.\n' +
        '1) 확정 정책은 근거 문서의 해당 절을 따릅니다.\n' +
        '2) 설계 제안·미결정 항목은 운영에 확정 값으로 쓰지 마세요.\n' +
        '<b>강조</b> 같은 표시는 해석하지 않습니다.',
      citations: [
        {
          docRef: 'MOCK-POLICY-COMMERCE',
          policyVersion: 3,
          asOf: { asOf: '2026-11-01T00:00:00Z', freshness: 'CURRENT' },
          title: '[목] 커머스 확정 정책',
          section: '§4.9',
          docVersion: 'v3',
          grounding: 'CONFIRMED_POLICY',
        },
        {
          docRef: 'MOCK-DESIGN-REGISTRATION',
          policyVersion: null,
          asOf: { asOf: '2026-10-30T00:00:00Z', freshness: 'STALE' },
          title: '[목] 상품 등록 설계',
          section: '§2',
          grounding: 'DESIGN_PROPOSAL',
        },
        { docRef: 'MOCK-OPEN-QUESTION', policyVersion: null, title: '[목] 미결정 사항', grounding: 'UNDECIDED' },
      ],
    };
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
        return answerFromWire(saved.wire);
      }
      const scenario = script(question);
      if (scenario === 'forbidden') throw problem(403, 'FORBIDDEN');
      if (scenario === 'unavailable') throw new UnknownResultFailure(problem(503, 'DEPENDENCY_UNAVAILABLE', true).problem, 'mock-unavailable');
      received.push({ key: key.value, question });
      const stored: Stored = { owner, question, wire: compose(question, scenario) };
      byKey.set(key.value, stored);
      byId.set(stored.wire.answerId ?? '', stored);
      if (scenario === 'lostOnce' && !lostOnce.has(key.value)) {
        lostOnce.add(key.value);
        throw new UnknownResultFailure('mock: 응답 유실', 'mock-lost');
      }
      return answerFromWire(stored.wire);
    },

    async get(answerId: string) {
      await wait();
      const owner = currentSubject();
      const saved = byId.get(answerId);
      // 남의 답변은 있는지도 알리지 않는다
      if (!owner || !saved || saved.owner !== owner) throw problem(404, 'NOT_FOUND');
      return answerFromWire(saved.wire);
    },

    async health() {
      await wait();
      return options.health?.() ?? 'UP';
    },
  };
}
