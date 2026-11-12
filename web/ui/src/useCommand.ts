// 변경 명령 1건의 상태. 키는 사용자 행위 단위로 보관한다.
// - 새 클릭(run) = 새 키. 결과 불명인 동안 run 은 막고, "다시 확인"(resend)은 같은 키·같은 본문으로 보낸다.
// - Problem·REJECTED 는 거절로 확정, 타임아웃·5xx·UNKNOWN_RESULT 는 불명(실패로 확정하지 않음).
import { useCallback, useLayoutEffect, useRef, useState } from 'react';

import { IdempotencyKey, NetworkFailure, PmartFailure, UnknownResultFailure } from '@pmart/web-core';

export type CommandPhase<T> =
  | { readonly kind: 'idle' }
  | { readonly kind: 'running' }
  | { readonly kind: 'done'; readonly result: T }
  | { readonly kind: 'rejected'; readonly failure: PmartFailure }
  | { readonly kind: 'unknown'; readonly failure: PmartFailure };

export interface Command<V, T> {
  readonly phase: CommandPhase<T>;
  /** 새 행위. 진행 중·결과 불명이면 무시한다. */
  readonly run: (vars: V) => Promise<CommandPhase<T>>;
  /** 결과 불명일 때 같은 키·같은 본문으로 다시 보낸다(멱등 재생 = 결과 확인). */
  readonly resend: () => Promise<CommandPhase<T>>;
  readonly reset: () => void;
  readonly busy: boolean;
}

export function useCommand<V, T>(fn: (vars: V, key: IdempotencyKey) => Promise<T>): Command<V, T> {
  const [phase, setPhaseState] = useState<CommandPhase<T>>({ kind: 'idle' });
  const phaseRef = useRef<CommandPhase<T>>({ kind: 'idle' });
  const pending = useRef<{ key: IdempotencyKey; vars: V } | null>(null);
  const fnRef = useRef(fn);
  useLayoutEffect(() => {
    fnRef.current = fn;
  });

  const setPhase = useCallback((next: CommandPhase<T>) => {
    phaseRef.current = next;
    setPhaseState(next);
  }, []);

  const send = useCallback(
    async (key: IdempotencyKey, vars: V): Promise<CommandPhase<T>> => {
      pending.current = { key, vars };
      setPhase({ kind: 'running' });
      let next: CommandPhase<T>;
      try {
        next = { kind: 'done', result: await fnRef.current(vars, key) };
        pending.current = null;
      } catch (e) {
        const failure = e instanceof PmartFailure ? e : new PmartFailure(String(e));
        if (failure instanceof UnknownResultFailure || failure instanceof NetworkFailure) {
          next = { kind: 'unknown', failure };
        } else {
          next = { kind: 'rejected', failure };
          pending.current = null;
        }
      }
      setPhase(next);
      return next;
    },
    [setPhase],
  );

  const run = useCallback(
    (vars: V) => {
      const k = phaseRef.current.kind;
      if (k === 'running' || k === 'unknown') return Promise.resolve(phaseRef.current);
      return send(IdempotencyKey.generate(), vars);
    },
    [send],
  );

  const resend = useCallback(() => {
    const p = pending.current;
    if (!p || phaseRef.current.kind === 'running') return Promise.resolve(phaseRef.current);
    return send(p.key, p.vars);
  }, [send]);

  const reset = useCallback(() => {
    const k = phaseRef.current.kind;
    if (k === 'unknown' || k === 'running') return;
    pending.current = null;
    setPhase({ kind: 'idle' });
  }, [setPhase]);

  return { phase, run, resend, reset, busy: phase.kind === 'running' || phase.kind === 'unknown' };
}
