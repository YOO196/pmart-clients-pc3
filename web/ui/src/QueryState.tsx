// UiState 7종(LOADING/READY/EMPTY/PARTIAL/ERROR/FORBIDDEN/RESULT_UNKNOWN) 표시. pmart_ui 의 UiStateView 와 같은 규칙.
import type { ReactNode } from 'react';

import {
  PmartFailure,
  ProblemCode,
  ProblemFailure,
  SessionExpiredFailure,
  UnknownResultFailure,
} from '@pmart/web-core';
import { uiMessages as m } from './messages';

export type UiState<T> =
  | { readonly kind: 'loading' }
  | { readonly kind: 'ready'; readonly data: T }
  | { readonly kind: 'empty' }
  | { readonly kind: 'partial'; readonly data: T; readonly missing: readonly string[] }
  | { readonly kind: 'error'; readonly failure: PmartFailure }
  | { readonly kind: 'forbidden'; readonly requestId?: string }
  | { readonly kind: 'unknown'; readonly requestId?: string };

/** 실패 → 화면 상태. 조회 실패를 empty 로 바꾸지 않는다. */
export function uiStateFromError<T>(error: unknown): UiState<T> {
  const failure = error instanceof PmartFailure ? error : new PmartFailure(String(error));
  if (failure instanceof UnknownResultFailure) {
    return failure.requestId ? { kind: 'unknown', requestId: failure.requestId } : { kind: 'unknown' };
  }
  if (failure instanceof ProblemFailure && failure.problem.code === ProblemCode.forbidden) {
    return failure.requestId ? { kind: 'forbidden', requestId: failure.requestId } : { kind: 'forbidden' };
  }
  return { kind: 'error', failure };
}

interface Props<T> {
  readonly state: UiState<T>;
  readonly children: (data: T) => ReactNode;
  readonly onRetry?: () => void;
  readonly onCheckAgain?: () => void;
  readonly emptyText?: string;
}

function RequestId({ id }: { readonly id: string | undefined }) {
  return id ? <p className="text-xs opacity-70 select-all">{m.requestId(id)}</p> : null;
}

export function QueryState<T>({ state, children, onRetry, onCheckAgain, emptyText }: Props<T>) {
  switch (state.kind) {
    case 'loading':
      return (
        <div role="status" data-state="loading" className="flex items-center gap-3 p-8">
          <span className="loading loading-spinner" />
          {m.loading}
        </div>
      );
    case 'ready':
      return <>{children(state.data)}</>;
    case 'empty':
      return (
        <p data-state="empty" className="p-8 opacity-70">
          {emptyText ?? m.empty}
        </p>
      );
    case 'partial':
      return (
        <div data-state="partial">
          <div role="alert" className="alert alert-warning mb-4">
            <span>{`${m.unavailableSources}: ${state.missing.join(', ')}`}</span>
            {onRetry && (
              <button type="button" className="btn btn-sm" onClick={onRetry}>
                {m.retry}
              </button>
            )}
          </div>
          {children(state.data)}
        </div>
      );
    case 'error': {
      const f = state.failure;
      const title =
        f instanceof SessionExpiredFailure
          ? m.sessionExpired
          : f instanceof ProblemFailure && f.problem.code === ProblemCode.configRequired
            ? m.configRequired
            : m.errorTitle;
      return (
        <div role="alert" data-state="error" className="alert alert-error flex-col items-start">
          <h2 className="font-bold">{title}</h2>
          <p>{m.errorBody}</p>
          <RequestId id={f.requestId} />
          {onRetry && (
            <button type="button" className="btn btn-sm" onClick={onRetry}>
              {m.retry}
            </button>
          )}
        </div>
      );
    }
    case 'forbidden':
      return (
        <div role="alert" data-state="forbidden" className="alert flex-col items-start">
          <h2 className="font-bold">{m.forbiddenTitle}</h2>
          <p>{m.forbiddenBody}</p>
          <RequestId id={state.requestId} />
        </div>
      );
    case 'unknown':
      return (
        <div role="alert" data-state="unknown" className="alert alert-info flex-col items-start">
          <h2 className="font-bold">{m.unknownTitle}</h2>
          <p>{m.unknownBody}</p>
          <RequestId id={state.requestId} />
          {onCheckAgain && (
            <button type="button" className="btn btn-sm btn-outline" onClick={onCheckAgain}>
              {m.checkAgain}
            </button>
          )}
        </div>
      );
  }
}
