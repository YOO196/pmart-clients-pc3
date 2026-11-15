// 화면이 쓰는 직원 세션(역할·센터) — `GET /employee-auth/sessions/current` 응답에서 읽는다(employee-auth 0.6.0,
// 백엔드 요청 2026-11-15 web-common-request-session-roles-centers). access token 은 API 서버가 읽는 값이라 화면이 그 내용에 기대지 않는다.
// 부르는 때: 토큰이 생기거나 바뀔 때(로그인·새로고침 복원·갱신 뒤)와 탭이 다시 보일 때(ADR-0061 확인과 같은 호출).
// - 응답과 토큰이 잠깐 다를 수 있다(권한 승인·회수 직후). 화면은 응답을 따르고, API 403 은 갱신 뒤 같아진다.
// - 이미 받은 값이 있으면 다시 부르는 동안·다시 부르다 실패해도 그 값을 그대로 둔다(다음 호출 때 맞춰진다). 처음 받기가 실패하면 실패로 둔다(빈 역할로 보이지 않는다).
// - 401 은 pmartFetch 의 401 처리 그대로다 — 갱신이 거절되면 store 가 비워져 'signed-out' 이 된다.
// 판정은 서버가 한다. 화면은 메뉴를 보이거나 안내하는 데만 쓴다.
import type { EmployeeAuthApi, EmployeeSession, SessionWatchDeps } from './employeeAuth';
import { watchEmployeeSessionOnVisible } from './employeeAuth';
import { request } from './pmartFetch';
import type { OperatorSession } from './session';
import type { TokenStore } from './tokens';

export type OperatorSessionState =
  /** 토큰이 없다(로그인 전·로그아웃·세션 끝남) */
  | { readonly status: 'signed-out' }
  /** 토큰은 있고 처음 받는 중 */
  | { readonly status: 'loading' }
  | { readonly status: 'ready'; readonly session: OperatorSession }
  /** 토큰은 있는데 처음 받기가 실패했다(네트워크·5xx 등) — 다시 시도(reload) */
  | { readonly status: 'failed'; readonly failure: unknown };

export interface OperatorSessionSource {
  readonly getState: () => OperatorSessionState;
  /** 상태가 바뀌면 알린다(useSyncExternalStore 용). 해제 함수 */
  readonly subscribe: (listener: () => void) => () => void;
  /** 지금 토큰으로 다시 받는다(실패 뒤 "다시 시도") */
  readonly reload: () => Promise<void>;
  /** 토큰 변화·탭 다시 보임을 보기 시작한다(지금 토큰이 있으면 바로 한 번 받는다). 해제 함수 */
  readonly start: (d?: Omit<SessionWatchDeps, 'check'>) => () => void;
}

/** 세션 응답 → 화면 세션 */
export function toOperatorSession(s: EmployeeSession): OperatorSession {
  const exp = Date.parse(s.expiresAt);
  return {
    subject: s.operatorId,
    type: 'OPERATOR',
    roles: [...s.roles],
    centers: [...s.centers],
    // 0.9.0 centerDetails — 이름이 null(서버가 못 읽음)인 센터는 넣지 않는다(코드로 보인다)
    centerNames: new Map((s.centerDetails ?? []).flatMap((c) => (c.name ? [[c.centerId, c.name] as const] : []))),
    sessionId: s.sessionId,
    ...(Number.isNaN(exp) ? {} : { expiresAtSeconds: Math.floor(exp / 1000) }),
  };
}

/**
 * 앱마다(Provider 마다) 하나 만든다.
 * `seed` 는 **시험 전용**(앱의 `initialToken` — 목 토큰으로 바로 세션을 시작할 때): 처음 상태를 'ready' 로 두고 start() 가 곧 서버 응답으로 바꾼다.
 * 실서버 경로(로그인·새로고침 복원)는 seed 없이 'loading' 에서 시작한다.
 */
export function createOperatorSessionSource(api: EmployeeAuthApi, store: TokenStore, seed?: OperatorSession | null): OperatorSessionSource {
  let state: OperatorSessionState =
    store.accessToken === null ? { status: 'signed-out' } : seed ? { status: 'ready', session: seed } : { status: 'loading' };
  const listeners = new Set<() => void>();
  /** 마지막으로 시작한 받기 — 늦게 온 옛 응답을 버린다 */
  let seq = 0;

  const set = (next: OperatorSessionState) => {
    state = next;
    for (const l of listeners) l();
  };

  async function load(): Promise<void> {
    if (store.accessToken === null) {
      seq += 1;
      if (state.status !== 'signed-out') set({ status: 'signed-out' });
      return;
    }
    const mine = (seq += 1);
    if (state.status !== 'ready' && state.status !== 'loading') set({ status: 'loading' });
    try {
      const s = await request('GET', api.employeeAuth.GET('/employee-auth/sessions/current', {}));
      if (mine !== seq) return;
      if (store.accessToken === null) set({ status: 'signed-out' });
      else set({ status: 'ready', session: toOperatorSession(s) });
    } catch (failure) {
      if (mine !== seq) return;
      if (store.accessToken === null) set({ status: 'signed-out' });
      else if (state.status !== 'ready') set({ status: 'failed', failure });
    }
  }

  function start(d: Omit<SessionWatchDeps, 'check'> = {}): () => void {
    const unsubscribe = store.subscribe(() => void load());
    const unwatch = watchEmployeeSessionOnVisible(api, store, { ...d, check: load });
    if (store.accessToken !== null || state.status !== 'signed-out') void load();
    return () => {
      unsubscribe();
      unwatch();
    };
  }

  return {
    getState: () => state,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    reload: load,
    start,
  };
}
