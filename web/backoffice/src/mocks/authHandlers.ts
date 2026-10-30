// auth-service 운영자 로그인 목(ADR-0018): 로그인·잠금, refresh 회전·재사용 감지, 로그아웃, 현재 세션, 비밀번호, 계정 관리.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { mockOperatorToken } from '../api/session';
import { db, nextId, timestamp, type MockAccount, type MockSession } from './db';
import { idempotent, operator, problem, unauthorized } from './support';

/** 목 수치(실서버는 보안 설정값): access 15분, 세션 12시간, 5회 실패 → 15분 잠금 */
export const mockAuthPolicy = { accessSeconds: 15 * 60, sessionHours: 12, maxFailures: 5, lockMinutes: 15 };

const findByLoginId = (loginId: string) => [...db.accounts.values()].find((a) => a.account.loginId === loginId);

function issue(acc: MockAccount, s: MockSession) {
  const exp = Math.floor(Date.now() / 1000) + mockAuthPolicy.accessSeconds;
  return {
    accessToken: mockOperatorToken({ sub: acc.account.operatorId, roles: acc.account.roles, centers: acc.account.centers, sid: s.sessionId, exp }),
    refreshToken: s.refreshToken,
    accessTokenExpiresAt: new Date(exp * 1000).toISOString(),
    refreshTokenExpiresAt: s.expiresAt,
    sessionId: s.sessionId,
  };
}

const passwordOk = (password: string, loginId: string) => password.length >= 10 && password !== loginId;

function requireAdmin(request: Request) {
  const who = operator(request);
  if (!who) return unauthorized();
  return who.roles.includes('OPERATOR_ADMIN') ? null : problem(403, 'FORBIDDEN');
}

const revokeSessionsOf = (operatorId: string) => {
  for (const s of db.sessions.values()) if (s.operatorId === operatorId) s.revoked = true;
};

export const authHandlers = [
  http.post(`${API_BASE}/auth/operator-logins`, async ({ request }) => {
    const body = (await request.json()) as { loginId?: string; password?: string };
    if (!body.loginId || !body.password) return problem(400, 'VALIDATION_FAILED');
    const acc = findByLoginId(body.loginId);
    if (acc?.account.lockedUntil && new Date(acc.account.lockedUntil).getTime() > Date.now()) return problem(423, 'ACCOUNT_LOCKED');
    if (!acc || acc.account.state !== 'ACTIVE' || acc.password !== body.password) {
      if (acc) {
        acc.failures += 1;
        if (acc.failures >= mockAuthPolicy.maxFailures) {
          acc.account = { ...acc.account, locked: true, lockedUntil: new Date(Date.now() + mockAuthPolicy.lockMinutes * 60_000).toISOString() };
          return problem(423, 'ACCOUNT_LOCKED');
        }
      }
      return problem(401, 'LOGIN_FAILED'); // 아이디 없음과 비밀번호 불일치를 구분하지 않는다
    }
    acc.failures = 0;
    acc.account = { ...acc.account, locked: false, lockedUntil: null, lastLoginAt: timestamp() };
    const session: MockSession = {
      sessionId: nextId('sess'),
      operatorId: acc.account.operatorId,
      deviceId: request.headers.get('X-Device-Id') ?? '',
      refreshToken: nextId('rt'),
      used: new Set(),
      revoked: false,
      issuedAt: timestamp(),
      expiresAt: new Date(Date.now() + mockAuthPolicy.sessionHours * 3600_000).toISOString(),
    };
    db.sessions.set(session.sessionId, session);
    return HttpResponse.json({ tokens: issue(acc, session), operator: acc.account });
  }),

  http.post(`${API_BASE}/auth/tokens`, async ({ request }) => {
    const { refreshToken } = (await request.json()) as { refreshToken: string };
    const s = [...db.sessions.values()].find((x) => x.refreshToken === refreshToken || x.used.has(refreshToken));
    if (!s || s.revoked || new Date(s.expiresAt).getTime() < Date.now()) return problem(401, 'TOKEN_INVALID');
    if (s.used.has(refreshToken)) {
      s.revoked = true; // 이미 쓴 토큰이 다시 왔다 → 탈취로 보고 세션 폐기
      return problem(401, 'TOKEN_REUSED');
    }
    if (request.headers.get('X-Device-Id') !== s.deviceId) return problem(401, 'TOKEN_INVALID');
    const acc = db.accounts.get(s.operatorId);
    if (!acc || acc.account.state !== 'ACTIVE') return problem(401, 'TOKEN_INVALID');
    s.used.add(refreshToken);
    s.refreshToken = nextId('rt');
    return HttpResponse.json(issue(acc, s)); // 역할·센터는 갱신 때 계정에서 다시 읽는다
  }),

  http.post(`${API_BASE}/auth/logouts`, ({ request }) => {
    const who = operator(request);
    const s = who?.sessionId ? db.sessions.get(who.sessionId) : undefined;
    if (s) s.revoked = true;
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(`${API_BASE}/auth/sessions/current`, ({ request }) => {
    const who = operator(request);
    if (!who) return problem(401, 'TOKEN_INVALID');
    const s = who.sessionId ? db.sessions.get(who.sessionId) : undefined;
    return HttpResponse.json({
      sessionId: who.sessionId ?? '',
      principalId: who.subject,
      principalType: 'OPERATOR',
      roles: [...who.roles],
      centerScope: [...who.centers],
      activeDelegationIds: [],
      ...(s ? { issuedAt: s.issuedAt, expiresAt: s.expiresAt } : {}),
    });
  }),

  http.post(`${API_BASE}/auth/password-changes`, async ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const body = (await request.json()) as { currentPassword: string; newPassword: string };
    const acc = db.accounts.get(who.subject);
    if (!acc || acc.password !== body.currentPassword) return problem(401, 'LOGIN_FAILED');
    if (!passwordOk(body.newPassword, acc.account.loginId)) return problem(422, 'PASSWORD_POLICY');
    acc.password = body.newPassword;
    acc.account = { ...acc.account, passwordChangeRequired: false, version: acc.account.version + 1 };
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(`${API_BASE}/operator-accounts`, ({ request }) => {
    const denied = requireAdmin(request);
    if (denied) return denied;
    const items = [...db.accounts.values()].map((a) => a.account).sort((a, b) => a.loginId.localeCompare(b.loginId));
    return HttpResponse.json({ items, page: { nextCursor: null, size: items.length } });
  }),

  http.post(`${API_BASE}/operator-accounts`, async ({ request }) => {
    const denied = requireAdmin(request);
    if (denied) return denied;
    const body = (await request.json()) as { loginId: string; displayName: string; initialPassword: string; roles: string[]; centers?: string[] };
    return idempotent(request, () => {
      if (findByLoginId(body.loginId)) return problem(409, 'LOGIN_ID_TAKEN');
      if (!passwordOk(body.initialPassword, body.loginId)) return problem(422, 'PASSWORD_POLICY');
      const operatorId = nextId('op');
      const account = {
        operatorId,
        loginId: body.loginId,
        displayName: body.displayName,
        roles: body.roles,
        centers: body.centers ?? [],
        state: 'ACTIVE' as const,
        locked: false,
        lockedUntil: null,
        passwordChangeRequired: true,
        lastLoginAt: null,
        version: 0,
        createdAt: timestamp(),
      };
      db.accounts.set(operatorId, { account, password: body.initialPassword, failures: 0 });
      return { status: 201, body: account };
    });
  }),

  http.get(`${API_BASE}/operator-accounts/:id`, ({ request, params }) => {
    const denied = requireAdmin(request);
    if (denied) return denied;
    const acc = db.accounts.get(String(params['id']));
    return acc ? HttpResponse.json(acc.account) : problem(404, 'NOT_FOUND');
  }),

  http.put(`${API_BASE}/operator-accounts/:id`, async ({ request, params }) => {
    const denied = requireAdmin(request);
    if (denied) return denied;
    const body = (await request.json()) as { displayName: string; roles: string[]; centers: string[]; state: 'ACTIVE' | 'DISABLED' };
    return idempotent(request, () => {
      const acc = db.accounts.get(String(params['id']));
      if (!acc) return problem(404, 'NOT_FOUND');
      const expected = request.headers.get('X-Expected-Version');
      if (expected !== null && Number(expected) !== acc.account.version) return problem(409, 'VERSION_CONFLICT');
      const self = operator(request)?.subject === acc.account.operatorId;
      if (self && (body.state === 'DISABLED' || !body.roles.includes('OPERATOR_ADMIN'))) return problem(409, 'INVALID_STATE');
      acc.account = { ...acc.account, ...body, version: acc.account.version + 1 };
      if (body.state === 'DISABLED') revokeSessionsOf(acc.account.operatorId);
      return { status: 200, body: acc.account };
    });
  }),

  http.post(`${API_BASE}/operator-accounts/:id/password-resets`, async ({ request, params }) => {
    const denied = requireAdmin(request);
    if (denied) return denied;
    const { temporaryPassword } = (await request.json()) as { temporaryPassword: string };
    const acc = db.accounts.get(String(params['id']));
    if (!acc) return problem(404, 'NOT_FOUND');
    if (!passwordOk(temporaryPassword, acc.account.loginId)) return problem(422, 'PASSWORD_POLICY');
    acc.password = temporaryPassword;
    acc.failures = 0;
    acc.account = { ...acc.account, locked: false, lockedUntil: null, passwordChangeRequired: true, version: acc.account.version + 1 };
    revokeSessionsOf(acc.account.operatorId);
    return new HttpResponse(null, { status: 204 });
  }),
];
