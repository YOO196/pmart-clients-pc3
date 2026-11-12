// 운영자 로그인·토큰 갱신·로그아웃 (auth-service, ADR-0018, 백엔드 handoff 2026-10-30 §1.1).
// - 로그인은 Idempotency-Key 를 받지 않는다(상태를 남기는 명령이 아님).
// - refresh token 은 한 번만 쓴다. 갱신은 pmartFetch 의 single-flight 한 곳에서만 부른다.
// - TOKEN_INVALID·TOKEN_REUSED·SESSION_EXPIRED 면 세션 종료(재로그인). 네트워크 오류는 종료로 단정하지 않는다.
// - 비밀번호·토큰은 로그·오류 문구에 남기지 않는다.
import type { Api } from './client';
import { IdempotencyKey, SOURCE_SYSTEM } from './command';
import { ProblemFailure } from '@pmart/web-core';
import type { components } from './generated/auth';
import { NO_IDEMPOTENCY_HEADER, PUBLIC_HEADER, request, requestNoContent } from '@pmart/web-core';
import type { TokenStore } from '@pmart/web-core';

export type OperatorAccount = components['schemas']['OperatorAccount'];
export type CurrentSession = components['schemas']['Session'];

/** 세션을 끝내야 하는 갱신 거절 코드 */
const SESSION_ENDING = new Set(['TOKEN_INVALID', 'TOKEN_REUSED', 'SESSION_EXPIRED']);

export const AuthProblem = {
  loginFailed: 'LOGIN_FAILED',
  accountLocked: 'ACCOUNT_LOCKED',
  passwordPolicy: 'PASSWORD_POLICY',
  loginIdTaken: 'LOGIN_ID_TAKEN',
} as const;

const publicHeaders = (extra: Record<string, string> = {}) => ({ headers: { [PUBLIC_HEADER]: '1', ...extra } });

export async function loginOperator(
  api: Api,
  store: TokenStore,
  credentials: { readonly loginId: string; readonly password: string },
): Promise<OperatorAccount> {
  store.clear();
  const result = await request(
    'POST',
    api.auth.POST('/auth/operator-logins', {
      params: { header: { 'X-Source-System': SOURCE_SYSTEM, 'X-Device-Id': store.deviceId } },
      ...publicHeaders({ [NO_IDEMPOTENCY_HEADER]: '1' }),
      body: { loginId: credentials.loginId, password: credentials.password },
    }),
  );
  store.setPair(result.tokens);
  return result.operator;
}

/**
 * pmartFetch 의 refresh 훅. 새 access token 을 돌려주고, 세션이 끝났으면 null.
 * 응답을 잃으면(결과 불명) 같은 refresh token 을 다시 보내지 않는다 — 서버가 재사용으로 보고 세션을 끊는다.
 */
export async function refreshOperatorTokens(api: Api, store: TokenStore): Promise<string | null> {
  const refreshToken = store.refreshToken;
  if (!refreshToken) return null;
  try {
    const pair = await request(
      'POST',
      api.auth.POST('/auth/tokens', {
        params: {
          header: {
            'Idempotency-Key': IdempotencyKey.generate().value,
            'X-Source-System': SOURCE_SYSTEM,
            'X-Device-Id': store.deviceId,
          },
        },
        ...publicHeaders(),
        body: { refreshToken },
      }),
    );
    store.setPair(pair);
    return pair.accessToken;
  } catch (e) {
    if (e instanceof ProblemFailure && SESSION_ENDING.has(e.problem.code)) return null;
    throw e;
  }
}

/** 서버 세션을 끝낸다. 결과와 관계없이 이 탭의 토큰은 지운다(로그아웃은 멱등). */
export async function logoutOperator(api: Api, store: TokenStore): Promise<void> {
  // 서버 응답이 실패·불명이어도 탭의 토큰은 지운다(access 는 최대 15분 남지만 이 탭에서는 더 쓰지 않는다).
  try {
    if (store.accessToken) {
      await requestNoContent(
        'POST',
        api.auth.POST('/auth/logouts', {
          params: { header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': SOURCE_SYSTEM } },
          body: {},
        }),
      );
    }
  } catch {
    // 서버 세션 종료를 확인하지 못해도 이 탭은 로그아웃한다(세션은 절대 수명으로 끝난다).
  } finally {
    store.clear();
  }
}
