// employee-auth-service 목(계약 employee-auth-service.yaml): 티켓 교환, refresh 회전·재사용 감지, 로그아웃, 현재 세션.
// 목 모드에는 Keycloak 이 없다 — 로그인 화면의 목 계정 버튼이 `mock.<운영자 ID>` 티켓으로 복귀 주소를 연다(SessionContext.startMockLogin).
// 티켓 교환부터는 실제와 같은 코드가 돈다(code_verifier·X-Device-Id 를 보내는지 여기서 확인한다). 인사팀 백오피스 목과 같은 방식.
import { http, HttpResponse } from 'msw';

import { mockOperatorToken } from '@pmart/web-core';
import { API_BASE } from '../api/client';
import { EMPLOYEE_APP } from '../api/employeeAuth';
import { db, nextId, timestamp, type MockSession } from './db';
import { operator, problem, unauthorized } from './support';

/** 목 수치(실서버는 보안 설정값): access 15분, 세션 12시간 */
export const mockAuthPolicy = { accessSeconds: 15 * 60, sessionHours: 12 };

export const MOCK_TICKET_PREFIX = 'mock.';

function issue(s: MockSession) {
  // 역할·센터는 발급·갱신 때마다 다시 읽는다(권한이 바뀌면 다음 갱신부터 토큰에 반영).
  const grant = db.grants.get(s.operatorId) ?? { roles: [], centers: [] };
  const exp = Math.floor(Date.now() / 1000) + mockAuthPolicy.accessSeconds;
  return {
    accessToken: mockOperatorToken({ sub: s.operatorId, roles: grant.roles, centers: grant.centers, sid: s.sessionId, exp }),
    refreshToken: s.refreshToken,
    accessTokenExpiresAt: new Date(exp * 1000).toISOString(),
    refreshTokenExpiresAt: new Date(new Date(s.issuedAt).getTime() + mockAuthPolicy.sessionHours * 3600_000).toISOString(),
    sessionId: s.sessionId,
  };
}

export const authHandlers = [
  http.post(`${API_BASE}/employee-auth/tokens`, async ({ request }) => {
    const body = (await request.json()) as { ticket?: string; codeVerifier?: string };
    const deviceId = request.headers.get('X-Device-Id');
    if (!body.ticket || !body.codeVerifier || body.codeVerifier.length < 43 || !deviceId) return problem(400, 'VALIDATION_FAILED');
    if (!body.ticket.startsWith(MOCK_TICKET_PREFIX)) return problem(401, 'TICKET_INVALID');
    const operatorId = body.ticket.slice(MOCK_TICKET_PREFIX.length);
    const grant = db.grants.get(operatorId);
    if (!grant) return problem(401, 'TICKET_INVALID');
    const session: MockSession = {
      sessionId: nextId('SES-mock'),
      operatorId,
      deviceId,
      refreshToken: nextId('rt-mock'),
      used: new Set(),
      revoked: false,
      issuedAt: timestamp(),
    };
    db.sessions.set(session.sessionId, session);
    return HttpResponse.json({ operatorId, roles: [...grant.roles], centers: [...grant.centers], tokens: issue(session) });
  }),

  http.post(`${API_BASE}/employee-auth/tokens/refresh`, async ({ request }) => {
    const { refreshToken } = (await request.json()) as { refreshToken: string };
    const s = [...db.sessions.values()].find((x) => x.refreshToken === refreshToken || x.used.has(refreshToken));
    if (!s || s.revoked) return problem(401, 'TOKEN_INVALID');
    if (s.used.has(refreshToken)) {
      s.revoked = true; // 이미 쓴 토큰이 다시 왔다 → 탈취로 보고 세션 폐기
      return problem(401, 'TOKEN_REUSED');
    }
    if (request.headers.get('X-Device-Id') !== s.deviceId) return problem(401, 'TOKEN_INVALID');
    s.used.add(refreshToken);
    s.refreshToken = nextId('rt-mock');
    return HttpResponse.json(issue(s));
  }),

  // 목에는 Keycloak 세션이 없다 → idpLogoutUri 없이 200(계약: "이미 끝난 세션이면 주소 없이 200" 과 같은 모양).
  http.post(`${API_BASE}/employee-auth/logouts`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const s = who.sessionId ? db.sessions.get(who.sessionId) : undefined;
    if (s) s.revoked = true;
    return HttpResponse.json({});
  }),

  http.get(`${API_BASE}/employee-auth/sessions/current`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const s = who.sessionId ? db.sessions.get(who.sessionId) : undefined;
    return HttpResponse.json({
      sessionId: who.sessionId ?? '',
      operatorId: who.subject,
      app: EMPLOYEE_APP,
      issuedAt: s?.issuedAt ?? timestamp(),
      expiresAt: new Date((who.expiresAtSeconds ?? Math.floor(Date.now() / 1000)) * 1000).toISOString(),
    });
  }),
];
