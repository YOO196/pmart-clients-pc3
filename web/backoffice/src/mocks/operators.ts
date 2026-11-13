// 목 모드 직원 계정(로그인 화면의 버튼). 역할 이름은 백엔드 handoff 2026-10-30 §2(설정값이라 바뀔 수 있음).
// 비밀번호는 없다 — 목 모드에는 Keycloak 이 없어 버튼이 목 티켓으로 바로 로그인한다(mocks/authHandlers.ts).
import { mockOperatorToken } from '@pmart/web-core';

export const mockAccounts = [
  { operatorId: 'op-admin-1', label: '관리자', roles: ['OPERATOR_ADMIN'], centers: [] },
  { operatorId: 'op-md-1', label: 'MD 김', roles: ['MD'], centers: [] },
  { operatorId: 'op-approver-1', label: '승인자 이', roles: ['PRODUCT_APPROVER', 'DISPLAY_APPROVER', 'PRICE_APPROVER'], centers: [] },
  { operatorId: 'op-center-1', label: '센터 박', roles: [], centers: ['MFC-BSN-01', 'CDC01'] },
] as const;

/** 테스트용: 로그인 없이 바로 세션을 여는 목 access token */
export const mockOperators = mockAccounts;

export const mockTokenFor = (o: (typeof mockAccounts)[number], sid = `sess-${o.operatorId}`) =>
  mockOperatorToken({ sub: o.operatorId, roles: o.roles, centers: o.centers, sid });
