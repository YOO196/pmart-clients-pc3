// 업무 도우미 연동 포트. 화면은 이 인터페이스만 안다.
// - 지금: 목 모드는 draftMock(계약 확정 전 화면용, BR-46), 실서버 모드(local·lan)는 notConnected(호출하지 않음).
// - 계약 확정 뒤: 생성 클라이언트(api/generated/ai-assistant) + pmartFetch(인증·Idempotency-Key·X-Source-System) + request()
//   로 어댑터를 만들어 여기에 끼운다. 화면·테스트는 그대로 둔다.
import type { IdempotencyKey } from '../../api/command';
import type { AssistantAnswer, AssistantHealth } from './model';

export interface AssistantPort {
  /** connected=false 면 화면은 호출하지 않고 "연결 전" 안내만 보인다. */
  readonly connected: boolean;
  /** 목이면 화면에 목 표시를 붙인다. */
  readonly mock: boolean;
  /** 목만: 시나리오 꼬리표(화면 안내용). */
  readonly mockHints?: readonly string[];
  /**
   * 질의. 실패는 PmartFailure 로 던진다(api/failure 분류 그대로):
   * Problem(4xx) = 거절 확정, UnknownResultFailure(타임아웃·5xx·응답 유실) = 결과 불명 → 같은 키로 다시 보낸다.
   */
  ask(question: string, key: IdempotencyKey): Promise<AssistantAnswer>;
  /** 답변 조회(질의의 짝 조회). 없거나 남의 답변이면 Problem NOT_FOUND. */
  get(answerId: string): Promise<AssistantAnswer>;
  health(): Promise<AssistantHealth>;
}

export class AssistantNotConnectedError extends Error {
  constructor() {
    super('ai-assistant-service 계약 확정 전(BR-46) — 호출하지 않는다');
  }
}

/** 실서버 모드 기본값. 계약이 초안이라 서버 동작을 추측해 부르지 않는다. */
export const notConnectedAssistant: AssistantPort = {
  connected: false,
  mock: false,
  ask: () => Promise.reject(new AssistantNotConnectedError()),
  get: () => Promise.reject(new AssistantNotConnectedError()),
  health: () => Promise.reject(new AssistantNotConnectedError()),
};
