import type { UseQueryResult } from '@tanstack/react-query';

import { uiStateFromError, type UiState } from './QueryState';

/** useQuery → UiState. isEmpty 가 참일 때만 empty(조회 실패는 empty 가 아니다). */
export function toUiState<T>(query: UseQueryResult<T>, isEmpty: (data: T) => boolean = () => false): UiState<T> {
  if (query.isPending) return { kind: 'loading' };
  if (query.isError) return uiStateFromError(query.error);
  return isEmpty(query.data) ? { kind: 'empty' } : { kind: 'ready', data: query.data };
}
