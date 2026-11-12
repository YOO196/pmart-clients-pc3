// 비동기 반영(승인 → 정본 반영) 확인용 짧은 폴링. 화면이 열려 있는 동안만 돈다.
// 기본 1초 간격·최대 30회(백엔드 handoff 2026-10-30 §1). 테스트는 pollConfig 를 줄여 쓴다.
import { PmartFailure } from './failure';

export const pollConfig = {
  intervalMs: 1000,
  maxAttempts: 30,
  sleep: (ms: number) => new Promise<void>((r) => setTimeout(r, ms)),
};

export type PollOutcome<T> =
  | { readonly kind: 'done'; readonly value: T }
  | { readonly kind: 'timeout'; readonly last?: T; readonly lastFailure?: PmartFailure };

/** done 이 참이 될 때까지 query 를 반복한다. 끝까지 아니면 timeout(실패가 아니다). */
export async function pollUntil<T>(
  query: () => Promise<T>,
  done: (value: T) => boolean,
  { signal }: { readonly signal?: AbortSignal } = {},
): Promise<PollOutcome<T>> {
  let last: T | undefined;
  let lastFailure: PmartFailure | undefined;
  for (let i = 0; i < pollConfig.maxAttempts; i++) {
    if (signal?.aborted) break;
    if (i > 0) await pollConfig.sleep(pollConfig.intervalMs);
    try {
      const value = await query();
      if (done(value)) return { kind: 'done', value };
      last = value;
    } catch (e) {
      if (!(e instanceof PmartFailure)) throw e;
      lastFailure = e;
    }
  }
  return {
    kind: 'timeout',
    ...(last === undefined ? {} : { last }),
    ...(lastFailure ? { lastFailure } : {}),
  };
}
