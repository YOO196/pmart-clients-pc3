// 직원 세션(employee-auth-service, app=hr-backoffice). access token 은 메모리, refresh token 은 HttpOnly 쿠키(ADR-0059 — 이 탭의 sessionStorage 에는 세션 ID 만. 목·시험은 본문 refresh token).
// 로그인: 게이트웨이 로그인 시작 → Keycloak 화면 → /auth/callback?ticket= → 티켓 교환. 401 → refresh 회전(pmartFetch), 갱신 거절 → 세션 종료.
// 화면에 보이는 역할·센터는 access token 클레임에서 읽는다(안내용. 판정은 서버).
// 로그인·갱신·로그아웃 로직은 @pmart/web-core(createEmployeeAuth) — 백오피스와 같은 코드다.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router';

import { parseOperatorToken, type OperatorSession } from '@pmart/web-core';
import { API_BASE, tokens } from '../api/client';
import {
  beginEmployeeLogin,
  beginSilentEmployeeLogin,
  browser,
  CALLBACK_PATH,
  canTrySilentLogin,
  completeEmployeeLogin,
  logoutEmployee,
  refreshEmployeeTokens,
} from '../api/employeeAuth';
import { clearSavedSession, loadSavedSession, syncSavedSession } from '../api/sessionPersistence';
import { messages as m } from '../shared/messages';
import { useApi } from './ApiContext';

interface SessionValue {
  readonly session: OperatorSession | null;
  /** 새로고침 뒤 보관한 refresh 로 세션을 되살리는 중. 끝날 때까지 로그인으로 보내지 않는다. */
  readonly restoring: boolean;
  /** 게이트웨이 로그인 시작 주소로 브라우저를 옮긴다(돌아올 앱 경로) */
  readonly startLogin: (from: string) => Promise<void>;
  /** 이 탭에서 조용한 로그인 확인(silent)을 아직 하지 않았다 — 로그인 버튼을 보이기 전에 한 번 한다 */
  readonly canTrySilentLogin: () => boolean;
  /**
   * 조용한 로그인 확인: 화면 없이 Keycloak 세션만 확인하러 브라우저를 옮긴다(→ /auth/callback?ticket= 또는 ?error=LOGIN_REQUIRED).
   * 옮겼으면 true, 이미 한 번 했으면 false(로그인 버튼을 보인다).
   */
  readonly startSilentLogin: (from: string) => Promise<boolean>;
  /**
   * 목 모드 전용: Keycloak 화면 대신 목 티켓으로 복귀 주소(앱 안 경로)를 돌려준다 — 호출한 쪽이 그 경로로 이동한다.
   * 티켓 교환부터는 실제와 같은 코드가 돈다.
   */
  readonly startMockLogin: (from: string, operatorId: string) => Promise<string>;
  /** 복귀 주소의 쿼리(ticket 또는 error)로 토큰을 받는다. 돌아갈 앱 경로 */
  readonly completeLogin: (params: URLSearchParams) => Promise<string>;
  /**
   * 로그아웃(SSO). 토큰을 지운 뒤 Keycloak 로그아웃 주소로 브라우저를 옮긴다(→ /login 으로 돌아온다).
   * 'idp-session-may-remain' = 서버 확인을 못 받아 Keycloak 세션이 남았을 수 있다(signOutUnconfirmed 로 로그인 화면에서 안내).
   */
  readonly logout: () => Promise<'done' | 'redirecting' | 'idp-session-may-remain'>;
  readonly signOutUnconfirmed: boolean;
}

const SessionContext = createContext<SessionValue | null>(null);

const fromToken = (access: string | null) => (access ? parseOperatorToken(access) : null);

export function SessionProvider({ initialToken, children }: { readonly initialToken?: string; readonly children: ReactNode }) {
  const api = useApi();
  const [session, setSession] = useState<OperatorSession | null>(() => {
    tokens.accessToken = initialToken ?? null;
    return fromToken(tokens.accessToken);
  });
  const [saved] = useState(() => (!initialToken && tokens.accessToken === null ? loadSavedSession() : null));
  const [restoring, setRestoring] = useState(saved !== null);
  const restoreStarted = useRef(false);
  const [signOutUnconfirmed, setSignOutUnconfirmed] = useState(false);

  // 토큰이 바뀌면(갱신·만료) 세션 표시를 따라가고, refresh 보관을 맞춘다(없으면 지운다).
  useEffect(
    () =>
      tokens.subscribe((access) => {
        setSession(fromToken(access));
        syncSavedSession(tokens);
      }),
    [],
  );

  // 새로고침 복원: 보관한 refresh 로 한 번 갱신한다. 세션이 끝났으면(거절) 보관을 지우고 로그인으로.
  // 네트워크 등으로 결과를 모르면 보관은 두고 이번에는 로그인으로 보낸다(다음 로드에서 다시 시도).
  useEffect(() => {
    if (!restoring || restoreStarted.current || !saved) return;
    restoreStarted.current = true;
    tokens.restore(saved);
    void refreshEmployeeTokens(api, tokens)
      .then((access) => {
        if (access === null) {
          tokens.clear();
          clearSavedSession();
        }
      })
      .catch(() => undefined)
      .finally(() => setRestoring(false));
  }, [api, restoring, saved]);

  const startLogin = useCallback(async (from: string) => {
    setSignOutUnconfirmed(false);
    browser.assign(await beginEmployeeLogin(API_BASE, from, tokens));
  }, []);

  const startSilentLogin = useCallback(async (from: string) => {
    const url = await beginSilentEmployeeLogin(API_BASE, from, tokens);
    if (url === null) return false;
    browser.assign(url);
    return true;
  }, []);

  const startMockLogin = useCallback(async (from: string, operatorId: string) => {
    setSignOutUnconfirmed(false);
    await beginEmployeeLogin(API_BASE, from, tokens); // verifier·기기 ID 를 실제와 같이 남긴다
    return `${CALLBACK_PATH}?ticket=${encodeURIComponent(`mock.${operatorId}`)}`;
  }, []);

  const completeLogin = useCallback((params: URLSearchParams) => completeEmployeeLogin(api, params, tokens), [api]);

  const logout = useCallback(async () => {
    const outcome = await logoutEmployee(api, tokens);
    if (outcome.idpLogoutUri) {
      browser.assign(outcome.idpLogoutUri);
      return 'redirecting' as const;
    }
    setSignOutUnconfirmed(outcome.idpSessionMayRemain);
    return outcome.idpSessionMayRemain ? ('idp-session-may-remain' as const) : ('done' as const);
  }, [api]);

  const value = useMemo(
    () => ({ session, restoring, startLogin, canTrySilentLogin, startSilentLogin, startMockLogin, completeLogin, logout, signOutUnconfirmed }),
    [session, restoring, startLogin, startSilentLogin, startMockLogin, completeLogin, logout, signOutUnconfirmed],
  );
  return <SessionContext value={value}>{children}</SessionContext>;
}

export function useSession(): SessionValue {
  const v = useContext(SessionContext);
  if (!v) throw new Error('SessionProvider 가 없다');
  return v;
}

/** 세션이 없으면 로그인 화면으로 보낸다(돌아올 경로를 쿼리에). 권한 판정은 서버. */
export function RequireSession({ children }: { readonly children: ReactNode }) {
  const { session, restoring } = useSession();
  const location = useLocation();
  if (session) return <>{children}</>;
  if (restoring) {
    return (
      <p role="status" className="p-6 text-sm opacity-70">
        {m.loading}
      </p>
    );
  }
  const from = `${location.pathname}${location.search}`;
  return <Navigate to={`/login?from=${encodeURIComponent(from)}`} replace />;
}
