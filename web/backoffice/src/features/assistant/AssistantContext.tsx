// 업무 도우미 포트 + 이 세션에서 받은 답변 목록(메모리만, 저장소에 두지 않는다).
// 계정이 바뀌거나 로그아웃하면(세션 subject 변경) 목록과 TanStack Query 의 ['assistant'] 캐시를 지운다.
import { useQueryClient } from '@tanstack/react-query';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { useSession } from '../../app/SessionContext';
import type { AnswerState, AssistantAnswer } from './model';
import type { AssistantPort } from './port';

export interface HistoryItem {
  readonly answerId: string;
  readonly question: string;
  readonly state: AnswerState;
  readonly receivedAt: string;
}

interface AssistantValue {
  readonly port: AssistantPort;
  /** 지금 계정(subject). 화면·캐시 키에 넣어 이전 사용자 데이터와 섞이지 않게 한다. */
  readonly owner: string | null;
  readonly history: readonly HistoryItem[];
  readonly remember: (question: string, answer: AssistantAnswer) => void;
}

const AssistantContext = createContext<AssistantValue | null>(null);

export const assistantQueryKey = (owner: string | null, ...rest: readonly string[]) => ['assistant', owner ?? '-', ...rest];

export function AssistantProvider({ port, children }: { readonly port: AssistantPort; readonly children: ReactNode }) {
  const { session } = useSession();
  const owner = session?.subject ?? null;
  const queryClient = useQueryClient();
  const [history, setHistory] = useState<{ owner: string | null; items: readonly HistoryItem[] }>({ owner, items: [] });
  const lastOwner = useRef(owner);

  useEffect(() => {
    if (lastOwner.current === owner) return;
    lastOwner.current = owner;
    queryClient.removeQueries({ queryKey: ['assistant'] });
    setHistory({ owner, items: [] });
  }, [owner, queryClient]);

  const remember = useCallback(
    (question: string, answer: AssistantAnswer) =>
      setHistory((h) =>
        h.owner !== owner
          ? h
          : {
              owner,
              items: [
                { answerId: answer.answerId, question, state: answer.state, receivedAt: new Date().toISOString() },
                ...h.items.filter((i) => i.answerId !== answer.answerId),
              ].slice(0, 50),
            },
      ),
    [owner],
  );

  // 렌더 중 계정이 바뀐 순간에도 이전 목록을 보이지 않는다
  const value = useMemo(
    () => ({ port, owner, history: history.owner === owner ? history.items : [], remember }),
    [port, owner, history, remember],
  );
  return <AssistantContext value={value}>{children}</AssistantContext>;
}

export function useAssistant(): AssistantValue {
  const v = useContext(AssistantContext);
  if (!v) throw new Error('AssistantProvider 가 없다');
  return v;
}
