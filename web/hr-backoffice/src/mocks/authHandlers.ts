// employee-auth-service 목(계약 employee-auth-service.yaml 0.1.0): 티켓 교환, refresh 회전·재사용 감지, 로그아웃, 현재 세션.
// 목 모드에는 Keycloak 이 없다 — 로그인 화면의 목 계정 버튼이 `mock.<운영자 ID>` 티켓으로 복귀 주소를 연다(SessionContext.startMockLogin).
// 티켓 교환부터는 실제와 같은 코드가 돈다(code_verifier·X-Device-Id 를 보내는지 여기서 확인한다).
import { http, HttpResponse } from 'msw';

import { mockOperatorToken } from '@pmart/web-core';
import { API_BASE } from '../api/client';
import { EMPLOYEE_APP } from '../api/employeeAuth';
import { db, nextSeq, timestamp, type MockSession } from './db';
import { operator, problem, unauthorized } from './support';

/** 목 수치(실서버는 보안 설정값): access 15분, 세션 12시간 */
export const mockAuthPolicy = { accessSeconds: 15 * 60, sessionHours: 12 };

export const MOCK_TICKET_PREFIX = 'mock.';

function issue(s: MockSession) {
  const grant = db.grants.get(s.operatorId) ?? { roles: [], centers: [] };
  const exp = Math.floor(Date.now() / 1000) + mockAuthPolicy.accessSeconds;
  return {
    accessToken: mockOperatorToken({ sub: s.operatorId, roles: grant.roles, centers: grant.centers, sid: s.sessionId, exp }),
    refreshToken: s.refreshToken,
    // 목은 본문 방식(BODY)이다 — 서비스 워커는 HttpOnly 쿠키를 심지 못한다. 쿠키 방식(COOKIE)은 시험에서 따로 본다.
    refreshTransport: 'BODY' as const,
    accessTokenExpiresAt: new Date(exp * 1000).toISOString(),
    refreshTokenExpiresAt: new Date(new Date(s.issuedAt).getTime() + mockAuthPolicy.sessionHours * 3600_000).toISOString(),
    sessionId: s.sessionId,
  };
}

const available = (operatorId: string) => db.employees.get(operatorId)?.employee.status === 'ACTIVE';

/** `GET /employee-auth/roles` 목(0.5.0) — 이름은 백엔드 설정 role-info 와 같게(2026-11-15). 순서 = order */
export const mockRoles = [
  ['OPERATOR_ADMIN', '운영 관리자'],
  ['HR_ADMIN', '인사 관리자'],
  ['CENTER_MASTER_APPROVER', '센터 기준정보 승인자'],
  ['CS_AGENT', '고객센터 상담원'],
  ['DISPLAY_APPROVER', '전시 승인자'],
  ['INVENTORY_APPROVER', '재고 승인자'],
  ['MD', 'MD(상품 담당)'],
  ['MFC_SUPERVISOR', '센터 관리자'],
  ['MFC_WORKER', '센터 작업자'],
  ['PRICE_APPROVER', '가격 승인자'],
  ['PRODUCT_APPROVER', '상품 승인자'],
  ['RIDER_OPS', '라이더 운영'],
  ['SERVICEABILITY_APPROVER', '배송 권역 승인자'],
].map(([code, name], i) => ({ code: code!, name: name!, centerScoped: code === 'MFC_SUPERVISOR' || code === 'MFC_WORKER', order: i + 1 }));

export const authHandlers = [
  http.get(`${API_BASE}/employee-auth/roles`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    return HttpResponse.json({ items: mockRoles });
  }),

  http.post(`${API_BASE}/employee-auth/tokens`, async ({ request }) => {
    const body = (await request.json()) as { ticket?: string; codeVerifier?: string };
    const deviceId = request.headers.get('X-Device-Id');
    if (!body.ticket || !body.codeVerifier || body.codeVerifier.length < 43 || !deviceId) return problem(400, 'VALIDATION_FAILED');
    if (!body.ticket.startsWith(MOCK_TICKET_PREFIX)) return problem(401, 'TICKET_INVALID');
    const operatorId = body.ticket.slice(MOCK_TICKET_PREFIX.length);
    if (!db.employees.has(operatorId)) return problem(401, 'TICKET_INVALID');
    if (!available(operatorId)) return problem(403, 'ACCOUNT_NOT_AVAILABLE');
    const session: MockSession = {
      sessionId: `SES-mock-${nextSeq()}`,
      operatorId,
      deviceId,
      refreshToken: `rt-mock-${nextSeq()}`,
      used: new Set(),
      revoked: false,
      issuedAt: timestamp(),
    };
    db.sessions.set(session.sessionId, session);
    const grant = db.grants.get(operatorId) ?? { roles: [], centers: [] };
    return HttpResponse.json({ operatorId, roles: [...grant.roles], centers: [...grant.centers], tokens: issue(session) });
  }),

  http.post(`${API_BASE}/employee-auth/tokens/refresh`, async ({ request }) => {
    const { refreshToken } = (await request.json()) as { refreshToken: string };
    const s = [...db.sessions.values()].find((x) => x.refreshToken === refreshToken || x.used.has(refreshToken));
    if (!s || s.revoked) return problem(401, 'TOKEN_INVALID');
    if (s.used.has(refreshToken)) {
      s.revoked = true; // 이미 쓴 토큰이 다시 왔다 → 세션 폐기
      return problem(401, 'TOKEN_REUSED');
    }
    if (request.headers.get('X-Device-Id') !== s.deviceId) return problem(401, 'TOKEN_INVALID');
    if (!available(s.operatorId)) return problem(401, 'ACCOUNT_NOT_AVAILABLE');
    s.used.add(refreshToken);
    s.refreshToken = `rt-mock-${nextSeq()}`;
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
    // 0.6.0: 지금 기준 역할·센터(목 계정이면 db.grants, 시험용 토큰만 있는 계정이면 토큰 값)
    const grant = db.grants.get(who.subject) ?? { roles: who.roles, centers: who.centers };
    return HttpResponse.json({
      sessionId: who.sessionId ?? '',
      operatorId: who.subject,
      roles: [...grant.roles],
      centers: [...grant.centers],
      app: EMPLOYEE_APP,
      issuedAt: s?.issuedAt ?? timestamp(),
      expiresAt: new Date((who.expiresAtSeconds ?? Math.floor(Date.now() / 1000)) * 1000).toISOString(),
    });
  }),
];
