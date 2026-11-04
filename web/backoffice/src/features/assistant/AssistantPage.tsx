// 업무 도우미(BO 내부 운영자용 정책·업무 절차 질의응답). 읽기 전용 — 어떤 도메인 변경 버튼·자동 실행도 두지 않는다.
// 질의는 useCommand: 새 전송 = 새 Idempotency-Key, 결과 불명(타임아웃·5xx·응답 유실)은 실패로 단정하지 않고 같은 키·같은 질문으로 다시 확인.
// 권한 판정은 서버(403 / FORBIDDEN_SCOPE). 메뉴를 숨겨 대신하지 않는다.
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Link, useParams } from 'react-router';

import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { CommandFeedback } from '../../shared/Feedback';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';
import { assistantQueryKey, useAssistant } from './AssistantContext';
import { AnswerView } from './AnswerView';
import type { AssistantAnswer } from './model';

const MAX_QUESTION = 2000; // 초안 계약 question maxLength

function NotConnected() {
  return (
    <div role="status" data-state="not-connected" className="alert alert-info flex-col items-start">
      <span className="font-bold">{m.assistant.notConnectedTitle}</span>
      <span>{m.assistant.notConnectedBody}</span>
    </div>
  );
}

function Header() {
  const { port } = useAssistant();
  return (
    <>
      <h1 className="text-xl font-bold">
        {m.assistant.title}
        {port.mock && <span className="badge badge-warning ml-2 align-middle">{m.assistant.mockBadge}</span>}
      </h1>
      <p className="text-sm opacity-70">{m.assistant.intro}</p>
    </>
  );
}

/** 서비스 장애(health DOWN)·상태 확인 실패. 상태 확인 실패는 장애로 단정하지 않는다(전송은 막지 않음). */
function HealthBanner({ down, unknown, onRetry }: { readonly down: boolean; readonly unknown: boolean; readonly onRetry: () => void }) {
  if (!down && !unknown) return null;
  return (
    <div role="alert" data-state={down ? 'service-down' : 'service-unknown'} className="alert alert-error flex-col items-start">
      <span className="font-bold">{down ? m.assistant.healthDownTitle : m.assistant.healthUnknownTitle}</span>
      {down && <span>{m.assistant.healthDownBody}</span>}
      <button type="button" className="btn btn-sm" onClick={onRetry}>
        {m.assistant.checkHealth}
      </button>
    </div>
  );
}

function AskView() {
  const { port, owner, history, remember } = useAssistant();
  const [question, setQuestion] = useState('');
  const health = useQuery({ queryKey: assistantQueryKey(owner, 'health'), queryFn: () => port.health() });
  const serviceDown = health.isSuccess && health.data !== 'UP';

  const [answeredQuestion, setAnsweredQuestion] = useState<string | null>(null);
  const ask = useCommand(async ({ q }: { q: string }, key) => {
    const answer = await port.ask(q, key);
    remember(q, answer);
    setAnsweredQuestion(q);
    return answer;
  });

  const trimmed = question.trim();
  const locked = ask.busy; // 진행 중·결과 불명이면 질문을 바꾸거나 새로 보내지 않는다(같은 키 재확인만)
  // 방금 답을 받은 질문을 그대로 다시 누르면 새 키로 중복 질의가 된다 — 질문을 고치거나 "새 질문"으로 시작한다
  const answeredSame = ask.phase.kind === 'done' && answeredQuestion === trimmed;
  const canSend = trimmed.length > 0 && trimmed.length <= MAX_QUESTION && !locked && !serviceDown && !answeredSame;

  return (
    <>
      <HealthBanner down={serviceDown} unknown={health.isError} onRetry={() => void health.refetch()} />
      {port.mockHints && <p className="text-xs opacity-60">{m.assistant.mockTags(port.mockHints.join(' '))}</p>}

      <form
        className="space-y-2 rounded-box bg-base-100 p-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (canSend) void ask.run({ q: trimmed });
        }}
      >
        <label className="block">
          <span className="text-sm font-bold">{m.assistant.questionLabel}</span>
          <textarea
            className="textarea mt-1 w-full"
            rows={3}
            maxLength={MAX_QUESTION}
            placeholder={m.assistant.questionPlaceholder}
            value={question}
            disabled={locked}
            onChange={(e) => setQuestion(e.target.value)}
          />
        </label>
        <div className="flex items-center gap-2">
          <button type="submit" className="btn btn-primary btn-sm" disabled={!canSend}>
            {m.assistant.send}
          </button>
          {ask.phase.kind === 'done' && (
            <button
              type="button"
              className="btn btn-ghost btn-sm"
              onClick={() => {
                ask.reset();
                setQuestion('');
              }}
            >
              {m.assistant.newQuestion}
            </button>
          )}
          <span className="ml-auto text-xs opacity-60">{m.assistant.counter(question.length, MAX_QUESTION)}</span>
        </div>
      </form>

      {ask.phase.kind === 'running' ? (
        <div role="status" className="flex items-center gap-2 text-sm">
          <span className="loading loading-spinner loading-sm" />
          {m.assistant.asking}
        </div>
      ) : (
        <CommandFeedback command={ask} unknown={{ body: m.assistant.unknownBody }}>
          {(answer: AssistantAnswer) => <AnswerView answer={answer} linkToDetail />}
        </CommandFeedback>
      )}

      <section className="space-y-2">
        <h2 className="font-bold">{m.assistant.history}</h2>
        <p className="text-xs opacity-60">{m.assistant.historyNote}</p>
        {history.length === 0 ? (
          <p className="text-sm opacity-70">{m.assistant.historyEmpty}</p>
        ) : (
          <ul className="space-y-1 text-sm">
            {history.map((h) => (
              <li key={h.answerId} className="flex gap-2">
                <Link className="link" to={`/assistant/answers/${encodeURIComponent(h.answerId)}`}>
                  {h.answerId}
                </Link>
                <span className="badge badge-ghost badge-sm">{m.assistant.state[h.state]}</span>
                <span className="truncate opacity-80">{h.question}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

export function AssistantPage() {
  const { port, owner } = useAssistant();
  return (
    <section className="max-w-3xl space-y-4">
      <Header />
      {/* 계정이 바뀌면 질문·명령 상태를 새로 시작한다(이전 사용자 질문이 남지 않게) */}
      {port.connected ? <AskView key={owner ?? '-'} /> : <NotConnected />}
    </section>
  );
}

/** 기존 답변 조회(질의의 짝 조회 GET). 조회 실패는 "근거 없음"이 아니라 오류로 보인다. */
export function AssistantAnswerPage() {
  const { answerId = '' } = useParams();
  const { port, owner } = useAssistant();
  const query = useQuery({
    queryKey: assistantQueryKey(owner, 'answer', answerId),
    queryFn: () => port.get(answerId),
    enabled: port.connected,
  });
  return (
    <section className="max-w-3xl space-y-4">
      <Header />
      <h2 className="font-bold">{m.assistant.detailTitle}</h2>
      {port.connected ? (
        <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
          {(answer) => <AnswerView answer={answer} />}
        </QueryState>
      ) : (
        <NotConnected />
      )}
      <Link className="link text-sm" to="/assistant">
        {m.assistant.back}
      </Link>
    </section>
  );
}
