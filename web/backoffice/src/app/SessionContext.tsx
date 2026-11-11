// 운영자 세션. access token 은 메모리, refresh token 은 이 탭의 sessionStorage(새로고침 복원용, BR-03 전 임시).
// 로그인 → 토큰 쌍, 401 → refresh 회전(pmartFetch), 갱신 거절 → 세션 종료.
// 새로고침하면 보관한 refresh 로 한 번 갱신해 세션을 되살린다(그동안은 로그인 화면으로 보내지 않는다).
// 화면에 보이는 역할·센터는 access token 클레임에서 읽는다(안내용. 판정은 서버).
// 로그인 방식(LOGIN_MODE): auth-service(아이디·비밀번호) 또는 Keycloak(로그인 화면으로 이동, PKCE — handoff 2026-11-11).
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router';

import { loginOperator, logoutOperator, type OperatorAccount } from '../api/auth';
import { refreshTokens, tokens } from '../api/client';
import { beginKeycloakLogin, completeKeycloakLogin, keycloakLogoutUrl, LOGIN_MODE, type LoginMode } from '../api/keycloak';
import { parseIdToken, parseOperatorToken, type OperatorSession } from '../api/session';
import { clearSavedSession, loadSavedSession, syncSavedSession } from '../api/sessionPersistence';
import { messages as m } from '../shared/messages';
import { useApi } from './ApiContext';

interface SessionValue {
  readonly session: OperatorSession | null;
  /** 새로고침 뒤 보관한 refresh 로 세션을 되살리는 중. 끝날 때까지 로그인으로 보내지 않는다. */
  readonly restoring: boolean;
  /** 로그인 응답의 계정(표시 이름·비밀번호 변경 필요). 새로고침·테스트 토큰이면 null */
  readonly operator: OperatorAccount | null;
  /** 표시 이름(auth-service 로그인 응답 또는 Keycloak ID 토큰 name). 모르면 null */
  readonly displayName: string | null;
  /** Keycloak ID 토큰의 auth_time(초). 없으면 표시하지 않는다 */
  readonly authTimeSeconds: number | null;
  readonly loginMode: LoginMode;
  /** Keycloak 로그인 화면으로 이동한다(돌아올 앱 경로). .well-known 을 못 읽으면 던진다 */
  readonly startKeycloakLogin: (from: string) => Promise<void>;
  /** Keycloak 에서 돌아온 쿼리로 토큰을 받는다. 돌아갈 앱 경로 */
  readonly completeKeycloakLogin: (params: URLSearchParams) => Promise<string>;
  readonly login: (credentials: { loginId: string; password: string }) => Promise<OperatorAccount>;
  readonly logout: () => Promise<void>;
  /** 비밀번호를 바꾼 뒤 안내를 끈다 */
  readonly passwordChanged: () => void;
}

const SessionContext = createContext<SessionValue | null>(null);

const fromToken = (access: string | null) => (access ? parseOperatorToken(access) : null);

export function SessionProvider({ initialToken, children }: { readonly initialToken?: string; readonly children: ReactNode }) {
  const api = useApi();
  const [session, setSession] = useState<OperatorSession | null>(() => {
    tokens.accessToken = initialToken ?? null;
    return fromToken(tokens.accessToken);
  });
  const [operator, setOperator] = useState<OperatorAccount | null>(null);
  const [idInfo, setIdInfo] = useState(() => parseIdToken(tokens.idToken));
  // 새로고침 복원 대상(보관한 refresh). 첫 렌더에서 한 번 읽는다.
  const [saved] = useState(() => (!initialToken && tokens.accessToken === null ? loadSavedSession() : null));
  const [restoring, setRestoring] = useState(saved !== null);
  const restoreStarted = useRef(false);

  // 토큰이 바뀌면(갱신·만료) 세션 표시를 따라가고, refresh 보관을 맞춘다(없으면 지운다).
  useEffect(
    () =>
      tokens.subscribe((access) => {
        setSession(fromToken(access));
        setIdInfo(parseIdToken(tokens.idToken));
        if (access === null) setOperator(null);
        syncSavedSession(tokens);
      }),
    [],
  );

  // 새로고침 복원: 보관한 refresh 로 한 번 갱신한다. 세션이 끝났으면(거절) 보관을 지우고 로그인으로.
  // 네트워크 등으로 결과를 모르면 보관은 두고 이번에는 로그인으로 보낸다(다음 로드에서 다시 시도).
  useEffect(() => {
    if (!restoring || restoreStarted.current || !saved) return;
    restoreStarted.current = true;
    tokens.restore(saved.refreshToken, saved.deviceId);
    void refreshTokens(api, tokens)
      .then((access) => {
        if (access === null) {
          tokens.clear();
          clearSavedSession();
        }
      })
      .catch(() => undefined)
      .finally(() => setRestoring(false));
  }, [api, restoring, saved]);

  const login = useCallback(
    async (credentials: { loginId: string; password: string }) => {
      const account = await loginOperator(api, tokens, credentials);
      setOperator(account);
      return account;
    },
    [api],
  );

  const logout = useCallback(async () => {
    if (LOGIN_MODE !== 'keycloak') return logoutOperator(api, tokens);
    // 탭의 토큰을 지우고 Keycloak 세션도 끝낸다(로그아웃 주소로 이동 → post_logout_redirect_uri /login 으로 돌아온다).
    const url = await keycloakLogoutUrl(tokens);
    if (url) globalThis.location.assign(url);
  }, [api]);
  const passwordChanged = useCallback(() => setOperator((o) => (o ? { ...o, passwordChangeRequired: false } : o)), []);
  const startKeycloakLogin = useCallback(async (from: string) => {
    globalThis.location.assign(await beginKeycloakLogin(from));
  }, []);
  const completeKeycloak = useCallback((params: URLSearchParams) => completeKeycloakLogin(params, tokens), []);

  const displayName = operator?.displayName ?? idInfo.name ?? null;
  const authTimeSeconds = idInfo.authTimeSeconds ?? null;
  const value = useMemo(
    () => ({
      session,
      restoring,
      operator,
      displayName,
      authTimeSeconds,
      loginMode: LOGIN_MODE,
      startKeycloakLogin,
      completeKeycloakLogin: completeKeycloak,
      login,
      logout,
      passwordChanged,
    }),
    [session, restoring, operator, displayName, authTimeSeconds, startKeycloakLogin, completeKeycloak, login, logout, passwordChanged],
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
