// 업무 도우미 실서버 어댑터(ai-assistant-service 1.1.0, 게이트웨이 /api/v1/assistant/**).
// 백엔드 handoff backoffice/2026-11-04-clients-request-ai-assistant, 2026-11-09 clients-notice-assistant-lan-generative(LAN 배포·생성 답변).
// - 인증·X-Source-System(backoffice-web)·401 갱신은 pmartFetch 가 한다. 질의에는 Idempotency-Key 를 붙인다.
// - 응답을 잃었거나(타임아웃·503) 202 처리 중이면 화면이 **같은 키·같은 질문으로 POST** 를 다시 보낸다(계약: 같은 키 = 같은 답,
//   409 INVALID_STATE 때 하라는 것도 같은 POST 다). 그래서 GET ?requestId= 는 따로 쓰지 않는다.
// - 질문·답변을 로그에 남기지 않는다.
import { request } from '@pmart/web-core';
import type { Api } from '../../api/client';
import { SOURCE_SYSTEM, type IdempotencyKey } from '../../api/command';
import type { AssistantPort } from './port';
import { answerFromWire, historyFromWire } from './wire';

export function createHttpAssistant(api: Pick<Api, 'assistant'>): AssistantPort {
  return {
    connected: true,
    mock: false,

    async ask(question: string, key: IdempotencyKey) {
      // 200 완료 또는 202 처리 중(state=PROCESSING) — 둘 다 PolicyAnswer 본문.
      const wire = await request(
        'POST',
        api.assistant.POST('/assistant/policy-questions', {
          params: { header: { 'Idempotency-Key': key.value, 'X-Source-System': SOURCE_SYSTEM } },
          body: { question },
        }),
      );
      return answerFromWire(wire, key.value);
    },

    async get(answerId: string) {
      const wire = await request('GET', api.assistant.GET('/assistant/policy-questions/{answerId}', { params: { path: { answerId } } }));
      return answerFromWire(wire);
    },

    async history(cursor?: string) {
      const wire = await request(
        'GET',
        api.assistant.GET('/assistant/question-history', {
          params: { header: { 'X-Source-System': SOURCE_SYSTEM }, query: cursor ? { cursor } : {} },
        }),
      );
      return historyFromWire(wire);
    },
  };
}
