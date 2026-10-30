// 운영자 세션(메모리 전용). 로그인 → 토큰 쌍, 401 → refresh 회전(pmartFetch), 갱신 거절 → 세션 종료.
// 화면에 보이는 역할·센터는 access token 클레임에서 읽는다(안내용. 판정은 서버).
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router';

import { loginOperator, logoutOperator, type OperatorAccount } from '../api/auth';
import { tokens } from '../api/client';
import { parseOperatorToken, type OperatorSession } from '../api/session';
import { useApi } from './ApiContext';

interface SessionValue {
  readonly session: OperatorSession | null;
  /** 로그인 응답의 계정(표시 이름·비밀번호 변경 필요). 새로고침·테스트 토큰이면 null */
  readonly operator: OperatorAccount | null;
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

  // 토큰이 바뀌면(갱신·만료) 세션 표시를 따라간다.
  useEffect(
    () =>
      tokens.subscribe((access) => {
        setSession(fromToken(access));
        if (access === null) setOperator(null);
      }),
    [],
  );

  const login = useCallback(
    async (credentials: { loginId: string; password: string }) => {
      const account = await loginOperator(api, tokens, credentials);
      setOperator(account);
      return account;
    },
    [api],
  );

  const logout = useCallback(() => logoutOperator(api, tokens), [api]);
  const passwordChanged = useCallback(() => setOperator((o) => (o ? { ...o, passwordChangeRequired: false } : o)), []);

  const value = useMemo(
    () => ({ session, operator, login, logout, passwordChanged }),
    [session, operator, login, logout, passwordChanged],
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
  const { session } = useSession();
  const location = useLocation();
  if (session) return <>{children}</>;
  const from = `${location.pathname}${location.search}`;
  return <Navigate to={`/login?from=${encodeURIComponent(from)}`} replace />;
}
