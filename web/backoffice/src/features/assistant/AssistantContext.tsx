// 업무 도우미 포트 + 지금 계정(subject).
// 계정이 바뀌거나 로그아웃하면(세션 subject 변경) TanStack Query 의 ['assistant'] 캐시(답변·내 질문 목록)를 지운다.
// 질문 목록은 서버(GET /assistant/question-history)가 정본이다 — 화면 메모리에 따로 두지 않는다.
import { useQueryClient } from '@tanstack/react-query';
import { createContext, useContext, useEffect, useMemo, useRef, type ReactNode } from 'react';

import { useSession } from '../../app/SessionContext';
import type { AssistantPort } from './port';

interface AssistantValue {
  readonly port: AssistantPort;
  /** 지금 계정(subject). 화면·캐시 키에 넣어 이전 사용자 데이터와 섞이지 않게 한다. */
  readonly owner: string | null;
}

const AssistantContext = createContext<AssistantValue | null>(null);

export const assistantQueryKey = (owner: string | null, ...rest: readonly string[]) => ['assistant', owner ?? '-', ...rest];

export function AssistantProvider({ port, children }: { readonly port: AssistantPort; readonly children: ReactNode }) {
  const { session } = useSession();
  const owner = session?.subject ?? null;
  const queryClient = useQueryClient();
  const lastOwner = useRef(owner);

  useEffect(() => {
    if (lastOwner.current === owner) return;
    lastOwner.current = owner;
    // 이전 계정 캐시만 지운다. 새 계정 조회는 이미 시작됐을 수 있어 같이 지우면 응답을 받을 관찰자가 사라진다.
    const mine = owner ?? '-';
    queryClient.removeQueries({ queryKey: ['assistant'], predicate: (q) => q.queryKey[1] !== mine });
  }, [owner, queryClient]);

  const value = useMemo(() => ({ port, owner }), [port, owner]);
  return <AssistantContext value={value}>{children}</AssistantContext>;
}

export function useAssistant(): AssistantValue {
  const v = useContext(AssistantContext);
  if (!v) throw new Error('AssistantProvider 가 없다');
  return v;
}
